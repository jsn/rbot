module Irc
module Utils

require 'resolv'
require 'net/http'
require 'net/https'
Net::HTTP.version_1_2

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

  def initialize(bot)
    @bot = bot
    @cache = Hash.new
    @headers = {
      'User-Agent' => "rbot http util #{$version} (http://linuxbrit.co.uk/rbot/)",
    }
    @last_response = nil
  end
  attr_reader :last_response
  attr_reader :headers

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
  def get_proxy(uri)
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
    return h
  end

  # uri::         uri to query (Uri object)
  # readtimeout:: timeout for reading the response
  # opentimeout:: timeout for opening the connection
  #
  # simple get request, returns (if possible) response body following redirs
  # and caching if requested
  # if a block is given, it yields the urls it gets redirected to
  # TODO we really need something to implement proper caching
  def get(uri_or_str, readtimeout=10, opentimeout=5, max_redir=@bot.config["http.max_redir"], cache=false)
    if uri_or_str.kind_of?(URI)
      uri = uri_or_str
    else
      uri = URI.parse(uri_or_str.to_s)
    end
    debug "Getting #{uri}"

    proxy = get_proxy(uri)
    proxy.open_timeout = opentimeout
    proxy.read_timeout = readtimeout

    begin
      proxy.start() {|http|
        yield uri.request_uri() if block_given?
	req = Net::HTTP::Get.new(uri.request_uri(), @headers)
	if uri.user and uri.password
          req.basic_auth(uri.user, uri.password)
	end
	resp = http.request(req)
        case resp
        when Net::HTTPSuccess
          if cache
	    debug "Caching #{uri.to_s}"
	    cache_response(uri.to_s, resp)
          end
          return resp.body
        when Net::HTTPRedirection
          if resp.key?('location')
            new_loc = URI.join(uri, resp['location'])
            debug "Redirecting #{uri} to #{new_loc}"
            yield new_loc if block_given?
            if max_redir > 0
              # If cache is an Array, we assume get was called by get_cached
              # because of a cache miss and that the first value of the Array
              # was the noexpire value. Since the cache miss might have been
              # caused by a redirection, we want to try get_cached again
              # TODO FIXME look at Python's httplib2 for a most likely
              # better way to handle all this mess
              if cache.kind_of?(Array)
                return get_cached(new_loc, readtimeout, opentimeout, max_redir-1, cache[0])
              else
                return get(new_loc, readtimeout, opentimeout, max_redir-1, cache)
              end
            else
              warning "Max redirection reached, not going to #{new_loc}"
            end
          else
            warning "Unknown HTTP redirection #{resp.inspect}"
          end
        else
          debug "HttpUtil.get return code #{resp.code} #{resp.body}"
        end
        @last_response = resp
        return nil
      }
    rescue StandardError, Timeout::Error => e
      error "HttpUtil.get exception: #{e.inspect}, while trying to get #{uri}"
      debug e.backtrace.join("\n")
    end
    @last_response = nil
    return nil
  end

  # just like the above, but only gets the head
  def head(uri_or_str, readtimeout=10, opentimeout=5, max_redir=@bot.config["http.max_redir"])
    if uri_or_str.kind_of?(URI)
      uri = uri_or_str
    else
      uri = URI.parse(uri_or_str.to_s)
    end

    proxy = get_proxy(uri)
    proxy.open_timeout = opentimeout
    proxy.read_timeout = readtimeout

    begin
      proxy.start() {|http|
        yield uri.request_uri() if block_given?
	req = Net::HTTP::Head.new(uri.request_uri(), @headers)
	if uri.user and uri.password
          req.basic_auth(uri.user, uri.password)
	end
	resp = http.request(req)
        case resp
        when Net::HTTPSuccess
          return resp
        when Net::HTTPRedirection
          debug "Redirecting #{uri} to #{resp['location']}"
          yield resp['location'] if block_given?
          if max_redir > 0
            return head( URI.parse(resp['location']), readtimeout, opentimeout, max_redir-1)
          else
            warning "Max redirection reached, not going to #{resp['location']}"
          end
        else
          debug "HttpUtil.head return code #{resp.code}"
        end
        @last_response = resp
        return nil
      }
    rescue StandardError, Timeout::Error => e
      error "HttpUtil.head exception: #{e.inspect}, while trying to get #{uri}"
      debug e.backtrace.join("\n")
    end
    @last_response = nil
    return nil
  end

  def cache_response(k, resp)
    begin
      if resp.key?('pragma') and resp['pragma'] == 'no-cache'
	debug "Not caching #{k}, it has Pragma: no-cache"
	return
      end
      # TODO should we skip caching if neither last-modified nor etag are present?
      now = Time.new
      u = Hash.new
      u = Hash.new
      u[:body] = resp.body
      u[:last_modified] = nil
      u[:last_modified] = Time.httpdate(resp['date']) if resp.key?('date')
      u[:last_modified] = Time.httpdate(resp['last-modified']) if resp.key?('last-modified')
      u[:expires] = now
      u[:expires] = Time.httpdate(resp['expires']) if resp.key?('expires')
      u[:revalidate] = false
      if resp.key?('cache-control')
	# TODO max-age
	case resp['cache-control']
	when /no-cache|must-revalidate/
	  u[:revalidate] = true
	end
      end
      u[:etag] = ""
      u[:etag] = resp['etag'] if resp.key?('etag')
      u[:count] = 1
      u[:first_use] = now
      u[:last_use] = now
    rescue => e
      error "Failed to cache #{k}/#{resp.to_hash.inspect}: #{e.inspect}"
      return
    end
    @cache[k] = u
    debug "Cached #{k}/#{resp.to_hash.inspect}: #{u.inspect_no_body}"
    debug "#{@cache.size} pages (#{@cache.keys.join(', ')}) cached up to now"
  end

  # For debugging purposes
  class ::Hash
    def inspect_no_body
      temp = self.dup
      temp.delete(:body)
      temp.inspect
    end
  end

  def expired?(uri, readtimeout, opentimeout)
    k = uri.to_s
    debug "Checking cache validity for #{k}"
    begin
      return true unless @cache.key?(k)
      u = @cache[k]

      # TODO we always revalidate for the time being

      if u[:etag].empty? and u[:last_modified].nil?
	# TODO max-age
	return true
      end

      proxy = get_proxy(uri)
      proxy.open_timeout = opentimeout
      proxy.read_timeout = readtimeout

      proxy.start() {|http|
	yield uri.request_uri() if block_given?
	headers = @headers.dup
	headers['If-None-Match'] = u[:etag] unless u[:etag].empty?
	headers['If-Modified-Since'] = u[:last_modified].rfc2822 if u[:last_modified]
        debug "Cache HEAD request headers: #{headers.inspect}"
	# FIXME TODO We might want to use a Get here
	# because if a 200 OK is returned we would get the new body
	# with one connection less ...
	req = Net::HTTP::Head.new(uri.request_uri(), headers)
	if uri.user and uri.password
	  req.basic_auth(uri.user, uri.password)
	end
	resp = http.request(req)
	debug "Checking cache validity of #{u.inspect_no_body} against #{resp.inspect}/#{resp.to_hash.inspect}"
	case resp
	when Net::HTTPNotModified
	  return false
	else
	  return true
	end
      }
    rescue => e
      error "Failed to check cache validity for #{uri}: #{e.inspect}"
      return true
    end
  end

  # gets a page from the cache if it's still (assumed to be) valid
  # TODO remove stale cached pages, except when called with noexpire=true
  def get_cached(uri_or_str, readtimeout=10, opentimeout=5,
                 max_redir=@bot.config['http.max_redir'],
                 noexpire=@bot.config['http.no_expire_cache'])
    if uri_or_str.kind_of?(URI)
      uri = uri_or_str
    else
      uri = URI.parse(uri_or_str.to_s)
    end
    debug "Getting cached #{uri}"

    if expired?(uri, readtimeout, opentimeout)
      debug "Cache expired"
      bod = get(uri, readtimeout, opentimeout, max_redir, [noexpire])
      def bod.cached?; false; end
    else
      k = uri.to_s
      debug "Using cache"
      @cache[k][:count] += 1
      @cache[k][:last_use] = Time.now
      bod = @cache[k][:body]
      def bod.cached?; true; end
    end
    unless noexpire
      remove_stale_cache
    end
    return bod
  end

  # We consider a page to be manually expired if it has no
  # etag and no last-modified and if any of the expiration
  # conditions are met (expire_time, max_cache_time, Expires)
  def manually_expired?(hash, time)
    auto = hash[:etag].empty? and hash[:last_modified].nil?
    # TODO max-age
    manual = (time - hash[:last_use] > @bot.config['http.expire_time']*60) or
             (time - hash[:first_use] > @bot.config['http.max_cache_time']*60) or
	     (hash[:expires] < time)
    return (auto and manual)
  end

  def remove_stale_cache
    debug "Removing stale cache"
    debug "#{@cache.size} pages before"
    begin
    now = Time.new
    @cache.reject! { |k, val|
       manually_expired?(val, now)
    }
    rescue => e
      error "Failed to remove stale cache: #{e.inspect}"
    end
    debug "#{@cache.size} pages after"
  end
end
end
end
