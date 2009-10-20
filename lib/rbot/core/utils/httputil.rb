#-- vim:sw=2:et
#++
#
# :title: rbot HTTP provider
#
# Author:: Tom Gilbert <tom@linuxbrit.co.uk>
# Author:: Giuseppe "Oblomov" Bilotta <giuseppe.bilotta@gmail.com>
# Author:: Dmitry "jsn" Kim <dmitry point kim at gmail point com>

require 'resolv'
require 'net/http'
require 'cgi'
require 'iconv'
begin
  require 'net/https'
rescue LoadError => e
  error "Couldn't load 'net/https':  #{e.pretty_inspect}"
  error "Secured HTTP connections will fail"
end

# To handle Gzipped pages
require 'stringio'
require 'zlib'

module ::Net
  class HTTPResponse
    attr_accessor :no_cache
    unless method_defined? :raw_body
      alias :raw_body :body
    end

    def body_charset(str=self.raw_body)
      ctype = self['content-type'] || 'text/html'
      return nil unless ctype =~ /^text/i || ctype =~ /x(ht)?ml/i

      charsets = ['latin1'] # should be in config

      if ctype.match(/charset=["']?([^\s"']+)["']?/i)
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

      charsets.reverse_each do |charset|
        # XXX: this one is really ugly, but i don't know how to make it better
        #  -jsn

        0.upto(5) do |off|
          begin
            debug "trying #{charset} / offset #{off}"
            return Iconv.iconv('utf-8//ignore',
                               charset,
                               str.slice(0 .. (-1 - off))).first
          rescue
            debug "conversion failed for #{charset} / offset #{off}"
          end
        end
      end
      return str
    end

    def decompress_body(str)
      method = self['content-encoding']
      case method
      when nil
        return str
      when /gzip/ # Matches gzip, x-gzip, and the non-rfc-compliant gzip;q=\d sent by some servers
        debug "gunzipping body"
        begin
          return Zlib::GzipReader.new(StringIO.new(str)).read
        rescue Zlib::Error => e
          # If we can't unpack the whole stream (e.g. because we're doing a
          # partial read
          debug "full gunzipping failed (#{e}), trying to recover as much as possible"
          ret = ""
          begin
            Zlib::GzipReader.new(StringIO.new(str)).each_byte { |byte|
              ret << byte
            }
          rescue
          end
          return ret
        end
      when 'deflate'
        debug "inflating body"
        # From http://www.koders.com/ruby/fid927B4382397E5115AC0ABE21181AB5C1CBDD5C17.aspx?s=thread:
        # -MAX_WBITS stops zlib from looking for a zlib header
        inflater = Zlib::Inflate.new(-Zlib::MAX_WBITS)
        begin
          return inflater.inflate(str)
        rescue Zlib::Error => e
          raise e
          # TODO
          # debug "full inflation failed (#{e}), trying to recover as much as possible"
        end
      when /^(?:iso-8859-\d+|windows-\d+|utf-8|utf8)$/i
        # B0rked servers (Freshmeat being one of them) sometimes return the charset
        # in the content-encoding; in this case we assume that the document has
        # a standarc content-encoding
        old_hsh = self.to_hash
        self['content-type']= self['content-type']+"; charset="+method.downcase
        warning "Charset vs content-encoding confusion, trying to recover: from\n#{old_hsh.pretty_inspect}to\n#{self.to_hash.pretty_inspect}"
        return str
      else
        debug self.to_hash
        raise "Unhandled content encoding #{method}"
      end
    end

    def cooked_body
      return self.body_to_utf(self.decompress_body(self.raw_body))
    end

    # Read chunks from the body until we have at least _size_ bytes, yielding
    # the partial text at each chunk. Return the partial body.
    def partial_body(size=0, &block)

      partial = String.new

      if @read
        debug "using body() as partial"
        partial = self.body
        yield self.body_to_utf(self.decompress_body(partial)) if block_given?
      else
        debug "disabling cache"
        self.no_cache = true
        self.read_body { |chunk|
          partial << chunk
          yield self.body_to_utf(self.decompress_body(partial)) if block_given?
          break if size and size > 0 and partial.length >= size
        }
      end

      return self.body_to_utf(self.decompress_body(partial))
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
    Bot::Config.register Bot::Config::IntegerValue.new('http.read_timeout',
      :default => 10, :desc => "Default read timeout for HTTP connections")
    Bot::Config.register Bot::Config::IntegerValue.new('http.open_timeout',
      :default => 20, :desc => "Default open timeout for HTTP connections")
    Bot::Config.register Bot::Config::BooleanValue.new('http.use_proxy',
      :default => false, :desc => "should a proxy be used for HTTP requests?")
    Bot::Config.register Bot::Config::StringValue.new('http.proxy_uri', :default => false,
      :desc => "Proxy server to use for HTTP requests (URI, e.g http://proxy.host:port)")
    Bot::Config.register Bot::Config::StringValue.new('http.proxy_user',
      :default => nil,
      :desc => "User for authenticating with the http proxy (if required)")
    Bot::Config.register Bot::Config::StringValue.new('http.proxy_pass',
      :default => nil,
      :desc => "Password for authenticating with the http proxy (if required)")
    Bot::Config.register Bot::Config::ArrayValue.new('http.proxy_include',
      :default => [],
      :desc => "List of regexps to check against a URI's hostname/ip to see if we should use the proxy to access this URI. All URIs are proxied by default if the proxy is set, so this is only required to re-include URIs that might have been excluded by the exclude list. e.g. exclude /.*\.foo\.com/, include bar\.foo\.com")
    Bot::Config.register Bot::Config::ArrayValue.new('http.proxy_exclude',
      :default => [],
      :desc => "List of regexps to check against a URI's hostname/ip to see if we should use avoid the proxy to access this URI and access it directly")
    Bot::Config.register Bot::Config::IntegerValue.new('http.max_redir',
      :default => 5,
      :desc => "Maximum number of redirections to be used when getting a document")
    Bot::Config.register Bot::Config::IntegerValue.new('http.expire_time',
      :default => 60,
      :desc => "After how many minutes since last use a cached document is considered to be expired")
    Bot::Config.register Bot::Config::IntegerValue.new('http.max_cache_time',
      :default => 60*24,
      :desc => "After how many minutes since first use a cached document is considered to be expired")
    Bot::Config.register Bot::Config::BooleanValue.new('http.no_expire_cache',
      :default => false,
      :desc => "Set this to true if you want the bot to never expire the cached pages")
    Bot::Config.register Bot::Config::IntegerValue.new('http.info_bytes',
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
        error e
        raise e
      end
    end
  end

  # Create the HttpUtil instance, associating it with Bot _bot_
  #
  def initialize(bot)
    @bot = bot
    @cache = Hash.new
    @headers = {
      'Accept-Charset' => 'utf-8;q=1.0, *;q=0.8',
      'Accept-Encoding' => 'gzip;q=1, deflate;q=1, identity;q=0.8, *;q=0.2',
      'User-Agent' =>
        "rbot http util #{$version} (#{Irc::Bot::SOURCE_URL})"
    }
    debug "starting http cache cleanup timer"
    @timer = @bot.timer.add(300) {
      self.remove_stale_cache unless @bot.config['http.no_expire_cache']
    }
  end

  # Clean up on HttpUtil unloading, by stopping the cache cleanup timer.
  def cleanup
    debug 'stopping http cache cleanup timer'
    @bot.timer.remove(@timer)
  end

  # This method checks if a proxy is required to access _uri_, by looking at
  # the values of config values +http.proxy_include+ and +http.proxy_exclude+.
  #
  # Each of these config values, if set, should be a Regexp the server name and
  # IP address should be checked against.
  #
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

  # _uri_:: URI to create a proxy for
  #
  # Return a net/http Proxy object, configured for proxying based on the
  # bot's proxy configuration. See proxy_required for more details on this.
  #
  def get_proxy(uri, options = {})
    opts = {
      :read_timeout => @bot.config["http.read_timeout"],
      :open_timeout => @bot.config["http.open_timeout"]
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

  # Internal method used to hanlde response _resp_ received when making a
  # request for URI _uri_.
  #
  # It follows redirects, optionally yielding them if option :yield is :all.
  #
  # Also yields and returns the final _resp_.
  #
  def handle_response(uri, resp, opts, &block) # :yields: resp
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
        if resp['set-cookie']
          debug "setting cookie #{resp['set-cookie']}"
          new_opts[:headers] ||= Hash.new
          new_opts[:headers]['Cookie'] = resp['set-cookie']
        end
        debug "following the redirect to #{new_loc}"
        return get_response(new_loc, new_opts, &block)
      else
        warning ":| redirect w/o location?"
      end
    end
    class << resp
      undef_method :body
      alias :body :cooked_body
    end
    unless resp['content-type']
      debug "No content type, guessing"
      resp['content-type'] =
        case resp['x-rbot-location']
        when /.html?$/i
          'text/html'
        when /.xml$/i
          'application/xml'
        when /.xhtml$/i
          'application/xml+xhtml'
        when /.(gif|png|jpe?g|jp2|tiff?)$/i
          "image/#{$1.sub(/^jpg$/,'jpeg').sub(/^tif$/,'tiff')}"
        else
          'application/octetstream'
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

  # _uri_::     uri to query (URI object or String)
  #
  # Generic http transaction method. It will return a Net::HTTPResponse
  # object or raise an exception
  #
  # If a block is given, it will yield the response (see :yield option)
  #
  # Currently supported _options_:
  #
  # method::     request method [:get (default), :post or :head]
  # open_timeout::     open timeout for the proxy
  # read_timeout::     read timeout for the proxy
  # cache::            should we cache results?
  # yield::      if :final [default], calls the block for the response object;
  #              if :all, call the block for all intermediate redirects, too
  # max_redir::  how many redirects to follow before raising the exception
  #              if -1, don't follow redirects, just return them
  # range::      make a ranged request (usually GET). accepts a string
  #              for HTTP/1.1 "Range:" header (i.e. "bytes=0-1000")
  # body::       request body (usually for POST requests)
  # headers::    additional headers to be set for the request. Its value must
  #              be a Hash in the form { 'Header' => 'value' }
  #
  def get_response(uri_or_s, options = {}, &block) # :yields: resp
    uri = uri_or_s.kind_of?(URI) ? uri_or_s : URI.parse(uri_or_s.to_s)
    unless URI::HTTP === uri
      if uri.scheme
        raise "#{uri.scheme.inspect} URI scheme is not supported"
      else
        raise "don't know what to do with #{uri.to_s.inspect}"
      end
    end

    opts = {
      :max_redir => @bot.config['http.max_redir'],
      :yield => :final,
      :cache => true,
      :method => :GET
    }.merge(options)

    resp = nil

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

    cached = @cache[cache_key]

    if opts[:cache] && cached
      debug "got cached"
      if !cached.expired?
        debug "using cached"
        cached.use
        return handle_response(uri, cached.response, opts, &block)
      end
    end

    headers = @headers.dup.merge(opts[:headers] || {})
    headers['Range'] = opts[:range] if opts[:range]
    headers['Authorization'] = opts[:auth_head] if opts[:auth_head]

    if opts[:cache] && cached && (req_class == Net::HTTP::Get)
      cached.setup_headers headers
    end

    req = req_class.new(uri.request_uri, headers)
    if uri.user && uri.password
      req.basic_auth(uri.user, uri.password)
      opts[:auth_head] = req['Authorization']
    end
    req.body = opts[:body] if req_class == Net::HTTP::Post
    debug "prepared request: #{req.to_hash.inspect}"

    begin
      get_proxy(uri, opts).start do |http|
        http.request(req) do |resp|
          resp['x-rbot-location'] = uri.to_s
          if Net::HTTPNotModified === resp
            debug "not modified"
            begin
              cached.revalidate(resp)
            rescue Exception => e
              error e
            end
            debug "reusing cached"
            resp = cached.response
          elsif Net::HTTPServerError === resp || Net::HTTPClientError === resp
            debug "http error, deleting cached obj" if cached
            @cache.delete(cache_key)
          end

          begin
            return handle_response(uri, resp, opts, &block)
          ensure
            if cached = CachedObject.maybe_new(resp) rescue nil
              debug "storing to cache"
              @cache[cache_key] = cached
            end
          end
        end
      end
    rescue Exception => e
      error e
      raise e.message
    end
  end

  # _uri_::     uri to query (URI object or String)
  #
  # Simple GET request, returns (if possible) response body following redirs
  # and caching if requested, yielding the actual response(s) to the optional
  # block. See get_response for details on the supported _options_
  #
  def get(uri, options = {}, &block) # :yields: resp
    begin
      resp = get_response(uri, options, &block)
      raise "http error: #{resp}" unless Net::HTTPOK === resp ||
        Net::HTTPPartialContent === resp
      return resp.body
    rescue Exception => e
      error e
    end
    return nil
  end

  # _uri_::     uri to query (URI object or String)
  #
  # Simple HEAD request, returns (if possible) response head following redirs
  # and caching if requested, yielding the actual response(s) to the optional
  # block. See get_response for details on the supported _options_
  #
  def head(uri, options = {}, &block) # :yields: resp
    opts = {:method => :head}.merge(options)
    begin
      resp = get_response(uri, opts, &block)
      # raise "http error #{resp}" if Net::HTTPClientError === resp ||
      #   Net::HTTPServerError == resp
      return resp
    rescue Exception => e
      error e
    end
    return nil
  end

  # _uri_::     uri to query (URI object or String)
  # _data_::    body of the POST
  #
  # Simple POST request, returns (if possible) response following redirs and
  # caching if requested, yielding the response(s) to the optional block. See
  # get_response for details on the supported _options_
  #
  def post(uri, data, options = {}, &block) # :yields: resp
    opts = {:method => :post, :body => data, :cache => false}.merge(options)
    begin
      resp = get_response(uri, opts, &block)
      raise 'http error' unless Net::HTTPOK === resp or Net::HTTPCreated === resp
      return resp
    rescue Exception => e
      error e
    end
    return nil
  end

  # _uri_::     uri to query (URI object or String)
  # _nbytes_::  number of bytes to get
  #
  # Partial GET request, returns (if possible) the first _nbytes_ bytes of the
  # response body, following redirs and caching if requested, yielding the
  # actual response(s) to the optional block. See get_response for details on
  # the supported _options_
  #
  def get_partial(uri, nbytes = @bot.config['http.info_bytes'], options = {}, &block) # :yields: resp
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
      error "Failed to remove stale cache: #{e.pretty_inspect}"
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
    super
  end
end

HttpUtilPlugin.new
