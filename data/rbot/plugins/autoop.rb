class AutoOP < Plugin
    def help(plugin, topic="")
        "perform autoop based on hostmask - usage: addop <hostmask> [channel channel ...], rmop <hostmask> [channel], list - list current ops. If you don't specify which channels, all channels are assumed"
    end
    
    def join(m)
      return if m.address?
      @registry.each { |mask,channels|
        if(Irc.netmaskmatch(mask, m.source) &&
            (channels.empty? || channels.include?(m.channel)))
          @bot.mode(m.channel, "+o", m.sourcenick)
          return
        end
      }
    end

    def add(m, params)
      @registry[params[:mask]] = params[:channels].dup
      m.okay
    end

    def rm(m, params)
      unless @registry.has_key?(params[:mask])
        m.reply @bot.lang.get('dunno')
        return
      end
      if (params[:channels] && @registry[params[:mask]] != nil)
        params[:channels].each do |c|
          @registry[params[:mask]] = @registry[params[:mask]].reject {|ele| ele =~ /^#{c}$/i}
        end
      elsif(!@registry.delete(params[:mask]))
        m.reply @bot.lang.get('dunno')
      else
        m.okay
      end
    end

    def list(m, params)
      if(@registry.length)
        @registry.each { |mask,channels|
          m.reply "#{mask} in #{channels.empty? ? 'all channels' : channels.join(', ')}"
        }
      else
        m.reply "No entrys"
      end
    end
end

plugin = AutoOP.new

plugin.map 'autoop list', :action => 'list'
plugin.map 'autoop add :mask *channels', :action => 'add'
plugin.map 'autoop add :mask', :action => 'add'
plugin.map 'autoop rm :mask *channels', :action => 'rm'
plugin.map 'autoop rm :mask', :action => 'rm'

