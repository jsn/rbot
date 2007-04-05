#-- vim:sw=2:et
#++
#
# :title: rbot HTTP provider
#
# Author:: Tom Gilbert <tom@linuxbrit.co.uk>
# Author:: Giuseppe "Oblomov" Bilotta <giuseppe.bilotta@gmail.com>
# Author:: Dmitry "jsn" Kim <dmitry point kim at gmail point com>
#
# Copyright:: (C) 2002-2005 Tom Gilbert
# Copyright:: (C) 2006 Tom Gilbert, Giuseppe Bilotta
# Copyright:: (C) 2007 Giuseppe Bilotta, Dmitry Kim

require 'resolv'
require 'net/http'
require 'iconv'
begin
  require 'net/https'
rescue LoadError => e
  error "Couldn't load 'net/https':  #{e.inspect}"
  error "Secured HTTP connections will fail"
end

module ::Net 
  class HTTPResponse 
    attr_accessor :no_cache 
    if !instance_methods.include?('raw_body')
      alias :raw_body :body
    end

    def body_charset(str=self.raw_body)
      ctype = self['content-type'] || 'text/html'
      return nil unless ctype =~ /^text/i || ctype =~ /x(ht)?ml/i

      charsets = ['latin1'] # should be in config

      if self['content-type'].match(/charset=["']?([^\s"']+)["']?/i)
        charsets << $1
        debug "charset #{charsets.last} added from header"
      end

      case str
      when /<\?xml\s[^>]*encoding=['"]([^\s"'>]+)["'][^>]*\?>/i
        charsets << $1
        debug "xml charset #{charsets.last} added from xml pi"
      when /<(meta\s[^>]*http-equiv=["']?Content-Type["']?[^>]*)>/i
        meta = $1
        if meta =~ /charset=['"]?([^\s'";]+)['"]?/
          charsets << $1
          debug "html charset #{charsets.last} added from meta"
        end
      end
      return charsets.uniq
    end

    def body_to_utf(str)
      charsets = self.body_charset(str) or return str

      charsets.reverse_each { |charset|
        begin
          return Iconv.iconv('utf-8//ignore', charset, str).first
        rescue
          debug "conversion failed for #{charset}"
        end
      }
      return str
    end

    def body
      return self.body_to_utf(self.raw_body)
    end

    # Read chunks from the body until we have at least _size_ bytes, yielding 
    # the partial text at each chunk. Return the partial body. 
    def partial_body(size=0, &block) 

      self.no_cache = true
      partial = String.new 

      self.read_body { |chunk| 
        partial << chunk 
        yield self.body_to_utf(partial) if block_given? 
        break if size and size > 0 and partial.length >= size 
      } 

      return self.body_to_utf(partial)
    end 
  end 
end

Net::HTTP.version_1_2

module ::Irc
module Utils

# class for making http requests easier (mainly for plugins to use)
# this class can check the bot proxy configuration to determine if a proxy
# needs to be used, which includes support for per-url proxy configuration.
class HttpUtil
    BotConfig.register BotConfigBooleanValue.new('http.use_proxy',
      :default => false, :desc => "should a proxy be used for HTTP requests?")
    BotConfig.register BotConfigStringValue.new('http.proxy_uri', :default => false,
      :desc => "Proxy server to use for HTTP requests (URI, e.g http://proxy.host:port)")
    BotConfig.register BotConfigStringValue.new('http.proxy_user',
      :default => nil,
      :desc => "User for authenticating with the http proxy (if required)")
    BotConfig.register BotConfigStringValue.new('http.proxy_pass',
      :default => nil,
      :desc => "Password for authenticating with the http proxy (if required)")
    BotConfig.register BotConfigArrayValue.new('http.proxy_include',
      :default => [],
      :desc => "List of regexps to check against a URI's hostname/ip to see if we should use the proxy to access this URI. All URIs are proxied by default if the proxy is set, so this is only required to re-include URIs that might have been excluded by the exclude list. e.g. exclude /.*\.foo\.com/, include bar\.foo\.com")
    BotConfig.register BotConfigArrayValue.new('http.proxy_exclude',
      :default => [],
      :desc => "List of regexps to check against a URI's hostname/ip to see if we should use avoid the proxy to access this URI and access it directly")
    BotConfig.register BotConfigIntegerValue.new('http.max_redir',
      :default => 5,
      :desc => "Maximum number of redirections to be used when getting a document")
    BotConfig.register BotConfigIntegerValue.new('http.expire_time',
      :default => 60,
      :desc => "After how many minutes since last use a cached document is considered to be expired")
    BotConfig.register BotConfigIntegerValue.new('http.max_cache_time',
      :default => 60*24,
      :desc => "After how many minutes since first use a cached document is considered to be expired")
    BotConfig.register BotConfigIntegerValue.new('http.no_expire_cache',
      :default => false,
      :desc => "Set this to true if you want the bot to never expire the cached pages")
    BotConfig.register BotConfigIntegerValue.new('http.info_bytes',
      :default => 8192,
      :desc => "How many bytes to download from a web page to find some information. Set to 0 to let the bot download the whole page.")

  class CachedObject
    attr_accessor :response, :last_used, :first_used, :count, :expires, :date

    def self.maybe_new(resp)
      debug "maybe new #{resp}"
      return nil if resp.no_cache
      return nil unless Net::HTTPOK === resp ||
      Net::HTTPMovedPermanently === resp ||
      Net::HTTPFound === resp ||
      Net::HTTPPartialContent === resp

      cc = resp['cache-control']
      return nil if cc && (cc =~ /no-cache/i)

      date = Time.now
      if d = resp['date']
        date = Time.httpdate(d)
      end

      return nil if resp['expires'] && (Time.httpdate(resp['expires']) < date)

      debug "creating cache obj"

      self.new(resp)
    end

    def use
      now = Time.now
      @first_used = now if @count == 0
      @last_used = now
      @count += 1
    end

    def expired?
      debug "checking expired?"
      if cc = self.response['cache-control'] && cc =~ /must-revalidate/
        return true
      end
      return self.expires < Time.now
    end

    def setup_headers(hdr)
      hdr['if-modified-since'] = self.date.rfc2822

      debug "ims == #{hdr['if-modified-since']}"

      if etag = self.response['etag']
        hdr['if-none-match'] = etag
        debug "etag: #{etag}"
      end
    end

    def revalidate(resp = self.response)
      @count = 0
      self.use
      self.date = resp.key?('date') ? Time.httpdate(resp['date']) : Time.now

      cc = resp['cache-control']
      if cc && (cc =~ /max-age=(\d+)/)
        self.expires = self.date + $1.to_i
      elsif resp.key?('expires')
        self.expires = Time.httpdate(resp['expires'])
      elsif lm = resp['last-modified']
        delta = self.date - Time.httpdate(lm)
        delta = 10 if delta <= 0
        delta /= 5
        self.expires = self.date + delta
      else
        self.expires = self.date + 300
      end
      # self.expires = Time.now + 10 # DEBUG
      debug "expires on #{self.expires}"

      return true
    end

    private
    def initialize(resp)
      @response = resp
      begin
        self.revalidate
        self.response.raw_body
      rescue Exception => e
        error e.message
        error e.backtrace.join("\n")
        raise e
      end
    end
  end

  def initialize(bot)
    @bot = bot
    @cache = Hash.new
    @headers = {
      'Accept-Charset' => 'utf-8;q=1.0, *;q=0.8',
      'User-Agent' =>
        "rbot http util #{$version} (http://linuxbrit.co.uk/rbot/)"
    } 
    debug "starting http cache cleanup timer"
    @timer = @bot.timer.add(300) {
      self.remove_stale_cache unless @bot.config['http.no_expire_cache']
    }
  end 

  def cleanup
    debug 'stopping http cache cleanup timer'
    @bot.timer.remove(@timer)
  end

  # if http_proxy_include or http_proxy_exclude are set, then examine the
  # uri to see if this is a proxied uri
  # the in/excludes are a list of regexps, and each regexp is checked against
  # the server name, and its IP addresses
  def proxy_required(uri)
    use_proxy = true
    if @bot.config["http.proxy_exclude"].empty? && @bot.config["http.proxy_include"].empty?
      return use_proxy
    end

    list = [uri.host]
    begin
      list.concat Resolv.getaddresses(uri.host)
    rescue StandardError => err
      warning "couldn't resolve host uri.host"
    end

    unless @bot.config["http.proxy_exclude"].empty?
      re = @bot.config["http.proxy_exclude"].collect{|r| Regexp.new(r)}
      re.each do |r|
        list.each do |item|
          if r.match(item)
            use_proxy = false
            break
          end
        end
      end
    end
    unless @bot.config["http.proxy_include"].empty?
      re = @bot.config["http.proxy_include"].collect{|r| Regexp.new(r)}
      re.each do |r|
        list.each do |item|
          if r.match(item)
            use_proxy = true
            break
          end
        end
      end
    end
    debug "using proxy for uri #{uri}?: #{use_proxy}"
    return use_proxy
  end

  # uri:: Uri to create a proxy for
  #
  # return a net/http Proxy object, which is configured correctly for
  # proxying based on the bot's proxy configuration.
  # This will include per-url proxy configuration based on the bot config
  # +http_proxy_include/exclude+ options.
  
  def get_proxy(uri, options = {})
    opts = {
      :read_timeout => 10,
      :open_timeout => 5
    }.merge(options)

    proxy = nil
    proxy_host = nil
    proxy_port = nil
    proxy_user = nil
    proxy_pass = nil

    if @bot.config["http.use_proxy"]
      if (ENV['http_proxy'])
        proxy = URI.parse ENV['http_proxy'] rescue nil
      end
      if (@bot.config["http.proxy_uri"])
        proxy = URI.parse @bot.config["http.proxy_uri"] rescue nil
      end
      if proxy
        debug "proxy is set to #{proxy.host} port #{proxy.port}"
        if proxy_required(uri)
          proxy_host = proxy.host
          proxy_port = proxy.port
          proxy_user = @bot.config["http.proxy_user"]
          proxy_pass = @bot.config["http.proxy_pass"]
        end
      end
    end

    h = Net::HTTP.new(uri.host, uri.port, proxy_host, proxy_port, proxy_user, proxy_port)
    h.use_ssl = true if uri.scheme == "https"

    h.read_timeout = opts[:read_timeout]
    h.open_timeout = opts[:open_timeout]
    return h
  end

  def handle_response(uri, resp, opts, &block)
    if Net::HTTPRedirection === resp && opts[:max_redir] >= 0
      if resp.key?('location')
        raise 'Too many redirections' if opts[:max_redir] <= 0
        yield resp if opts[:yield] == :all && block_given?
        loc = resp['location']
        new_loc = URI.join(uri.to_s, loc) rescue URI.parse(loc)
        new_opts = opts.dup
        new_opts[:max_redir] -= 1
        case opts[:method].to_s.downcase.intern
        when :post, :"net::http::post"
          new_opts[:method] = :get
        end
        debug "following the redirect to #{new_loc}"
        return get_response(new_loc, new_opts, &block)
      else
        warning ":| redirect w/o location?"
      end
    end
    if block_given?
      yield(resp)
    else
      # Net::HTTP wants us to read the whole body here
      resp.raw_body
    end
    return resp
  end

  # uri::         uri to query (Uri object or String)
  # opts::        options. Currently used:
  # :method::     request method [:get (default), :post or :head]
  # :open_timeout::     open timeout for the proxy
  # :read_timeout::     read timeout for the proxy
  # :cache::            should we cache results?
  # :yield::      if :final [default], call &block for the response object
  #               if :all, call &block for all intermediate redirects, too
  # :max_redir::  how many redirects to follow before raising the exception
  #               if -1, don't follow redirects, just return them
  # :range::      make a ranged request (usually GET). accepts a string
  #               for HTTP/1.1 "Range:" header (i.e. "bytes=0-1000")
  # :body::       request body (usually for POST requests)
  #
  # Generic http transaction method
  #
  # It will return a HTTP::Response object or raise an exception
  #
  # If a block is given, it will yield the response (see :yield option)

  def get_response(uri_or_s, options = {}, &block)
    uri = uri_or_s.kind_of?(URI) ? uri_or_s : URI.parse(uri_or_s.to_s)
    opts = {
      :max_redir => @bot.config['http.max_redir'],
      :yield => :final,
      :cache => true,
      :method => :GET
    }.merge(options)

    resp = nil
    cached = nil

    req_class = case opts[:method].to_s.downcase.intern
                when :head, :"net::http::head"
                  opts[:max_redir] = -1
                  Net::HTTP::Head
                when :get, :"net::http::get"
                  Net::HTTP::Get
                when :post, :"net::http::post"
                  opts[:cache] = false
                  opts[:body] or raise 'post request w/o a body?'
                  warning "refusing to cache POST request" if options[:cache]
                  Net::HTTP::Post
                else
                  warning "unsupported method #{opts[:method]}, doing GET"
                  Net::HTTP::Get
                end

    if req_class != Net::HTTP::Get && opts[:range]
      warning "can't request ranges for #{req_class}"
      opts.delete(:range)
    end

    cache_key = "#{opts[:range]}|#{req_class}|#{uri.to_s}"

    if req_class != Net::HTTP::Get && req_class != Net::HTTP::Head
      if opts[:cache]
        warning "can't cache #{req_class.inspect} requests, working w/o cache"
        opts[:cache] = false
      end
    end

    debug "get_response(#{uri}, #{opts.inspect})"

    if opts[:cache] && cached = @cache[cache_key]
      debug "got cached"
      if !cached.expired?
        debug "using cached"
        cached.use
        return handle_response(uri, cached.response, opts, &block)
      end
    end
    
    headers = @headers.dup.merge(opts[:headers] || {})
    headers['Range'] = opts[:range] if opts[:range]

    cached.setup_headers(headers) if cached && (req_class == Net::HTTP::Get)
    req = req_class.new(uri.request_uri, headers)
    req.basic_auth(uri.user, uri.password) if uri.user && uri.password
    req.body = opts[:body] if req_class == Net::HTTP::Post
    debug "prepared request: #{req.to_hash.inspect}"

    get_proxy(uri, opts).start do |http|
      http.request(req) do |resp|
        resp['x-rbot-location'] = uri.to_s
        if Net::HTTPNotModified === resp
          debug "not modified"
          begin
            cached.revalidate(resp)
          rescue Exception => e
            error e.message
            error e.backtrace.join("\n")
          end
          debug "reusing cached"
          resp = cached.response
        elsif Net::HTTPServerError === resp || Net::HTTPClientError === resp
          debug "http error, deleting cached obj" if cached
          @cache.delete(cache_key)
        elsif opts[:cache]
          begin
            return handle_response(uri, resp, opts, &block)
          ensure
            if cached = CachedObject.maybe_new(resp) rescue nil
              debug "storing to cache"
              @cache[cache_key] = cached
            end
          end
          return ret
        end
        return handle_response(uri, resp, opts, &block)
      end
    end
  end

  # uri::         uri to query (Uri object)
  #
  # simple get request, returns (if possible) response body following redirs
  # and caching if requested
  def get(uri, opts = {}, &block)
    begin
      resp = get_response(uri, opts, &block)
      raise "http error: #{resp}" unless Net::HTTPOK === resp ||
        Net::HTTPPartialContent === resp
      return resp.body
    rescue Exception => e
      error e.message
      error e.backtrace.join("\n")
    end
    return nil
  end

  def head(uri, options = {}, &block)
    opts = {:method => :head}.merge(options)
    begin
      resp = get_response(uri, opts, &block)
      raise "http error #{resp}" if Net::HTTPClientError === resp ||
        Net::HTTPServerError == resp
      return resp
    rescue Exception => e
      error e.message
      error e.backtrace.join("\n")
    end
    return nil
  end

  def post(uri, data, options = {}, &block)
    opts = {:method => :post, :body => data, :cache => false}.merge(options)
    begin
      resp = get_response(uri, opts, &block)
      raise 'http error' unless Net::HTTPOK === resp
      return resp
    rescue Exception => e
      error e.message
      error e.backtrace.join("\n")
    end
    return nil
  end

  def get_partial(uri, nbytes = @bot.config['http.info_bytes'], options = {}, &block)
    opts = {:range => "bytes=0-#{nbytes}"}.merge(options)
    return get(uri, opts, &block)
  end

  def remove_stale_cache
    debug "Removing stale cache"
    now = Time.new
    max_last = @bot.config['http.expire_time'] * 60
    max_first = @bot.config['http.max_cache_time'] * 60
    debug "#{@cache.size} pages before"
    begin
      @cache.reject! { |k, val|
        (now - val.last_used > max_last) || (now - val.first_used > max_first)
      }
    rescue => e
      error "Failed to remove stale cache: #{e.inspect}"
    end
    debug "#{@cache.size} pages after"
  end

end
end
end

class HttpUtilPlugin < CoreBotModule
  def initialize(*a)
    super(*a)
    debug 'initializing httputil'
    @bot.httputil = Irc::Utils::HttpUtil.new(@bot)
  end

  def cleanup
    debug 'shutting down httputil'
    @bot.httputil.cleanup
    @bot.httputil = nil
  end
end

HttpUtilPlugin.new
