require 'net/http'
require 'uri/common'

Net::HTTP.version_1_2

class GooglePlugin < Plugin
  def help(plugin, topic="")
    "search <string> => search google for <string>"
  end
  def privmsg(m)
    unless(m.params && m.params.length > 0)
      m.reply "incorrect usage: " + help(m.plugin)
      return
    end
    searchfor = URI.escape m.params

    query = "/search?q=#{searchfor}&btnI=I%27m%20feeling%20lucky"
    result = "not found!"

    proxy_host = nil
    proxy_port = nil

    if(ENV['http_proxy'])
      if(ENV['http_proxy'] =~ /^http:\/\/(.+):(\d+)$/)
        proxy_host = $1
        proxy_port = $2
      end
    end

    http = Net::HTTP.new("www.google.com", 80, proxy_host, proxy_port)

    http.start {|http|
      begin
        resp , = http.get(query)
        if resp.code == "302"
          result = resp['location']
        end
      rescue => e
        p e
        if e.response && e.response['location']
          result = e.response['location']
        else
          result = "error!"
        end
      end
    }
    m.reply "#{m.params}: #{result}"
  end
end
plugin = GooglePlugin.new
plugin.register("search")
