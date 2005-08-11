class AutoOP < Plugin
    @@handlers = {
        "add" => "handle_addop",
        "rm" => "handle_rmop",
        "list" => "handle_listop"
    }
    
    def help(plugin, topic="")
        "perform autoop based on hostmask - usage: addop <hostmask>, rmop <hostmask>, listop"
    end
    
    def join(m)
        if(!m.address?)
          @registry.each { |mask,channels|
            if(Irc.netmaskmatch(mask, m.source) && channels.include?(m.channel))
              @bot.mode(m.channel, "+o", m.sourcenick)
            end
          }
        end
    end
    
    def privmsg(m)
        if(m.private?)
          if (!m.params || m.params == "list")
            handle_listop(m)
          elsif (m.params =~ /^add\s+(.+)$/)
            handle_addop(m, $1)
          elsif (m.params =~ /^rm\s+(.+)$/)
            handle_rmop(m, $1)
          end
        else
          m.reply "private message only please!"
        end
    end

    def handle_addop(m, params)
        ma = /^(.+?)(\s+(.+))?$/.match(params)
        channels = ma[2] ? ma[2] : @bot.config['irc.join_channels']
        if(ma[1] && channels)
            @registry[ma[1]] = channels
            m.okay
        else
            m.reply @bot.lang.get('dunno')
        end
    end

    def handle_rmop(m, params)
       if(!@registry.delete(params))
         m.reply @bot.lang.get('dunno')
       else
         m.okay
       end
    end

    def handle_listop(m)
        if(@registry.length)
            @registry.each { |mask,channels|
                m.reply "#{mask} in #{channels.join(', ')}"
            }
        else
            m.reply "No entrys"
        end
    end
end

plugin = AutoOP.new
plugin.register("autoop")

