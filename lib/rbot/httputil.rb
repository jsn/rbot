module Irc
module Utils

require 'resolv'
require 'net/http'
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
      :desc => "List of regexps to check against a URI's hostname/ip to see if we should use avoid the proxy to access this URI and access it directly")

  def initialize(bot)
    @bot = bot
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
      list.push Resolv.getaddresses(uri.host)
    rescue StandardError => err
      puts "warning: couldn't resolve host uri.host"
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
        proxy = URI.parse ENV['http_proxy']
      end
      if (@bot.config["http.proxy_uri"])
        proxy = URI.parse ENV['http_proxy_uri']
      end
      if proxy
        debug "proxy is set to #{proxy.uri}"
        if proxy_required(uri)
          proxy_host = proxy.host
          proxy_port = proxy.port
          proxy_user = @bot.config["http.proxy_user"]
          proxy_pass = @bot.config["http.proxy_pass"]
        end
      end
    end
    
    return Net::HTTP.new(uri.host, uri.port, proxy_host, proxy_port, proxy_user, proxy_port)
  end

  # uri::         uri to query (Uri object)
  # readtimeout:: timeout for reading the response
  # opentimeout:: timeout for opening the connection
  #
  # simple get request, returns response body if the status code is 200 and
  # the request doesn't timeout.
  def get(uri, readtimeout=10, opentimeout=5)
    proxy = get_proxy(uri)
    proxy.open_timeout = opentimeout
    proxy.read_timeout = readtimeout
   
    begin
      proxy.start() {|http|
        resp = http.get(uri.request_uri(), @headers)
        if resp.code == "200"
          return resp.body
        else
          puts "HttpUtil.get return code #{resp.code} #{resp.body}"
        end
        return nil
      }
    rescue StandardError, Timeout::Error => e
      $stderr.puts "HttpUtil.get exception: #{e}, while trying to get #{uri}"
    end
    return nil
  end
end
end
end
