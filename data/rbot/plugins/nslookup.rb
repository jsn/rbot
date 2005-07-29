class DnsPlugin < Plugin
  require 'resolv'
  def gethostname(address)
    Resolv.getname(address)
  end
  def getaddresses(name)
    Resolv.getaddresses(name)
  end

  def help(plugin, topic="")
    "dns <hostname|ip> => show local resolution results for hostname or ip address"
  end
  
  def name_to_ip(m, params)
    Thread.new do
      begin
        a = getaddresses(params[:host])
        if a.length > 0
          m.reply m.params + ": " + a.join(", ")
        else
          m.reply "#{params[:host]}: not found"
        end
      rescue StandardError => err
        m.reply "#{params[:host]}: not found"
      end
    end
  end
  
  def ip_to_name(m, params)
    Thread.new do
       begin
         a = gethostname(params[:ip])
         m.reply m.params + ": " + a if a
       rescue StandardError => err
         m.reply "#{params[:ip]}: not found (does not reverse resolve)"
       end
     end
  end
end
plugin = DnsPlugin.new
plugin.map 'dns :ip', :action => 'ip_to_name', 
                      :requirements => {:ip => /^\d+\.\d+\.\d+\.\d+$/}
plugin.map 'dns :host', :action => 'name_to_ip'
