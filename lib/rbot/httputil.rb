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
    if uri_or_str.class <= URI
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
        resp = http.get(uri.request_uri(), @headers)
        case resp
        when Net::HTTPSuccess
          if cache && !(resp.key?('cache-control') && resp['cache-control']=='must-revalidate')
            k = uri.to_s
            @cache[k] = Hash.new
            @cache[k][:body] = resp.body
            @cache[k][:last_mod] = Time.httpdate(resp['last-modified']) if resp.key?('last-modified')
            if resp.key?('date')
              @cache[k][:first_use] = Time.httpdate(resp['date'])
              @cache[k][:last_use] = Time.httpdate(resp['date'])
            else
              now = Time.new
              @cache[k][:first_use] = now
              @cache[k][:last_use] = now
            end
            @cache[k][:count] = 1
          end
          return resp.body
        when Net::HTTPRedirection
          debug "Redirecting #{uri} to #{resp['location']}"
          yield resp['location'] if block_given?
          if max_redir > 0
            return get( URI.parse(resp['location']), readtimeout, opentimeout, max_redir-1, cache)
          else
            warning "Max redirection reached, not going to #{resp['location']}"
          end
        else
          debug "HttpUtil.get return code #{resp.code} #{resp.body}"
        end
        return nil
      }
    rescue StandardError, Timeout::Error => e
      error "HttpUtil.get exception: #{e.inspect}, while trying to get #{uri}"
      debug e.backtrace.join("\n")
    end
    return nil
  end

  # just like the above, but only gets the head
  def head(uri_or_str, readtimeout=10, opentimeout=5, max_redir=@bot.config["http.max_redir"])
    if uri_or_str.class <= URI
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
        resp = http.head(uri.request_uri(), @headers)
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
        return nil
      }
    rescue StandardError, Timeout::Error => e
      error "HttpUtil.head exception: #{e.inspect}, while trying to get #{uri}"
      debug e.backtrace.join("\n")
    end
    return nil
  end

  # gets a page from the cache if it's still (assumed to be) valid
  # TODO remove stale cached pages, except when called with noexpire=true
  def get_cached(uri_or_str, readtimeout=10, opentimeout=5,
                 max_redir=@bot.config['http.max_redir'],
                 noexpire=@bot.config['http.no_expire_cache'])
    if uri_or_str.class <= URI
      uri = uri_or_str
    else
      uri = URI.parse(uri_or_str.to_s)
    end

    k = uri.to_s
    if !@cache.key?(k)
      remove_stale_cache unless noexpire
      return get(uri, readtimeout, opentimeout, max_redir, true)
    end
    now = Time.new
    begin
      # See if the last-modified header can be used
      # Assumption: the page was not modified if both the header
      # and the cached copy have the last-modified value, and it's the same time
      # If only one of the cached copy and the header have the value, or if the
      # value is different, we assume that the cached copyis invalid and therefore
      # get a new one.
      # On our first try, we tested for last-modified in the webpage first,
      # and then on the local cache. however, this is stupid (in general),
      # so we only test for the remote page if the local copy had the header
      # in the first place.
      if @cache[k].key?(:last_mod)
        h = head(uri, readtimeout, opentimeout, max_redir)
        if h.key?('last-modified')
          if Time.httpdate(h['last-modified']) == @cache[k][:last_mod]
            if h.key?('date')
              @cache[k][:last_use] = Time.httpdate(h['date'])
            else
              @cache[k][:last_use] = now
            end
            @cache[k][:count] += 1
            return @cache[k][:body]
          end
          remove_stale_cache unless noexpire
          return get(uri, readtimeout, opentimeout, max_redir, true)
        end
        remove_stale_cache unless noexpire
        return get(uri, readtimeout, opentimeout, max_redir, true)
      end
    rescue => e
      warning "Error #{e.inspect} getting the page #{uri}, using cache"
      debug e.backtrace.join("\n")
      return @cache[k][:body]
    end
    # If we still haven't returned, we are dealing with a non-redirected document
    # that doesn't have the last-modified attribute
    debug "Could not use last-modified attribute for URL #{uri}, guessing cache validity"
    if noexpire or !expired?(@cache[k], now)
      @cache[k][:count] += 1
      @cache[k][:last_use] = now
      debug "Using cache"
      return @cache[k][:body]
    end
    debug "Cache expired, getting anew"
    @cache.delete(k)
    remove_stale_cache unless noexpire
    return get(uri, readtimeout, opentimeout, max_redir, true)
  end

  def expired?(hash, time)
    (time - hash[:last_use] > @bot.config['http.expire_time']*60) or
    (time - hash[:first_use] > @bot.config['http.max_cache_time']*60)
  end

  def remove_stale_cache
    now = Time.new
    @cache.reject! { |k, val|
      !val.key?(:last_modified) && expired?(val, now)
    }
  end

end
end
end
