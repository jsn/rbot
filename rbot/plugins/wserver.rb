require 'net/http'
require 'uri'
Net::HTTP.version_1_2

class WserverPlugin < Plugin
  def help(plugin, topic="")
    "wserver <uri> => try and determine what webserver <uri> is using"
  end
  def privmsg(m)
    unless(m.params && m.params =~ /^\S+$/)
      m.reply "incorrect usage: " + help(m.plugins)
      return
    end

    proxy_host = nil
    proxy_port = nil

    if(ENV['http_proxy'])
      if(ENV['http_proxy'] =~ /^http:\/\/(.+):(\d+)$/)
        hh = $1
        pp = $2
        unless(m.params =~ /\.db\.com/ || m.params =~ /\.deuba\.com/)
          proxy_host = hh
          proxy_port = pp
        end
      end
    end

    redirect_count = 0
    hostname = m.params.dup
    begin
      if(redirect_count > 3)
        m.reply "cowardly refusing to follow more than 3 redirects"
        return
      end
      
      begin
        uri = URI.parse(hostname)
      rescue URI::InvalidURIError => err
        m.reply "#{m.params} is not a valid URI"
        return
      end
      
      unless(uri)
        m.reply "incorrect usage: " + help(m.plugin)
        return
      end
      if(uri.scheme == "https")
        m.reply "#{uri.scheme} not supported"
        return
      end
        
      host = uri.host ? uri.host : hostname
      port = uri.port ? uri.port : 80
      path = '/'
      if(uri.scheme == "http")
        path = uri.path if uri.path
      end
    
      http = Net::HTTP.new(host, port, proxy_host, proxy_port)
      http.open_timeout = 5
      
      http.start {|http|
        resp = http.head(path)
        result = host
        server = resp['Server']
        if(server && server.length > 0)
          m.reply "#{host} is running #{server}"
        else
          m.reply "couldn't tell what #{host} is running"
        end
        
        if(resp.code == "302" || resp.code == "301") 
          if(host != URI.parse(resp['location']).host)
            m.reply "#{host} redirects to #{resp['location']}"
            raise resp['location']
          end
        end
      }
    rescue TimeoutError => err
      m.reply "timed out connecting to #{host}:#{port} :("
      return
    rescue RuntimeError => err
      redirect_count += 1
      hostname = err.message
      retry
    rescue StandardError => err
      m.reply "couldn't connect to #{host}:#{port} :("
      return
    end
  end
end
plugin = WserverPlugin.new
plugin.register("wserver")
