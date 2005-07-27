class DnsPlugin < Plugin
  begin
    require 'resolv-replace'
    def gethostname(address)
      Resolv.getname(address)
    end
    def getaddresses(name)
      Resolv.getaddresses(name)
    end
  rescue LoadError
    def gethostname(address)
      Socket.gethostbyname(address).first
    end
    def getaddresses(name)
      a = Socket.gethostbyname(name)
      list = Socket.getaddrinfo(a[0], 'http')
      addresses = Array.new
      list.each {|line|
       addresses << line[3]
      }
      addresses
    end
  end

  def help(plugin, topic="")
    "nslookup|dns <hostname|ip> => show local resolution results for hostname or ip address"
  end
  def privmsg(m)
    unless(m.params)
      m.reply "incorrect usage: " + help(m.plugin)
      return
    end
    Thread.new do
      if(m.params =~ /^\d+\.\d+\.\d+\.\d+$/)
       begin
         a = gethostname(m.params)
         m.reply m.params + ": " + a if a
       rescue StandardError => err
         m.reply "#{m.params}: not found"
       end
      elsif(m.params =~ /^\S+$/)
       begin
         a = getaddresses(m.params)
         m.reply m.params + ": " + a.join(", ")
       rescue StandardError => err
         m.reply "#{m.params}: not found"
       end
      else
       m.reply "incorrect usage: " + help(m.plugin)
      end
    end
  end
end
plugin = DnsPlugin.new
plugin.register("nslookup")
plugin.register("dns")
