module Irc

require 'net/http'
Net::HTTP.version_1_2
  
# class for making http requests easier (mainly for plugins to use)
# this class can check the bot proxy configuration to determine if a proxy
# needs to be used, which includes support for per-url proxy configuration.
class HttpUtil
  def initialize(bot)
    @bot = bot
    @headers = {
      'User-Agent' => "rbot http util #{$version} (http://linuxbrit.co.uk/rbot/)",
    }
  end

  # uri:: Uri to create a proxy for
  #
  # return a net/http Proxy object, which is configured correctly for
  # proxying based on the bot's proxy configuration. 
  # This will include per-url proxy configuration based on the bot config
  # +http_proxy_include/exclude+ options.
  def get_proxy(uri)
    proxy = nil
    if (ENV['http_proxy'])
      proxy = URI.parse ENV['http_proxy']
    end
    if (@bot.config["http.proxy"])
      proxy = URI.parse ENV['http_proxy']
    end

    # if http_proxy_include or http_proxy_exclude are set, then examine the
    # uri to see if this is a proxied uri
    # the excludes are a list of regexps, and each regexp is checked against
    # the server name, and its IP addresses
    if uri
      if @bot.config["http.proxy_exclude"]
        # TODO
      end
      if @bot.config["http.proxy_include"]
      end
    end
    
    proxy_host = nil
    proxy_port = nil
    proxy_user = nil
    proxy_pass = nil
    if @bot.config["http.proxy_user"]
      proxy_user = @bot.config["http.proxy_user"]
      if @bot.config["http.proxy_pass"]
        proxy_pass = @bot.config["http.proxy_pass"]
      end
    end
    if proxy
      proxy_host = proxy.host
      proxy_port = proxy.port
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
