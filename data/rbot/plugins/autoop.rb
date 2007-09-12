class AutoOP < Plugin
  Config.register Config::BooleanValue.new('autoop.on_nick',
    :default => true,
    :desc => "Determines if the bot should auto-op when someone changes nick and the new nick matches a listed netmask")

  def help(plugin, topic="")
    return "perform autoop based on hostmask - usage: add <hostmask> [channel channel ...], rm <hostmask> [channel], list - list current ops. If you don't specify which channels, all channels are assumed"
  end

  def join(m)
    return if m.address?
    @registry.each { |mask,channels|
      if m.source.matches?(mask.to_irc_netmask(:server => m.server)) &&
        (channels.empty? || channels.include?(m.channel.to_s))
        @bot.mode(m.channel, "+o", m.source.nick)
        return
      end
    }
  end

  def nick(m)
    return if m.address?
    return unless @bot.config['autoop.on_nick']
    is_on = m.server.channels.inject(ChannelList.new) { |list, ch|
      list << ch if ch.users.include?(m.source)
      list
    }
    is_on.each { |channel|
      ch = channel.to_s
      @registry.each { |mask,channels|
        if m.source.matches?(mask.to_irc_netmask(:server => m.server)) &&
          (channels.empty? || channels.include?(ch))
          @bot.mode(ch, "+o", m.source.nick)
          return
        end
      }
    }
  end

  def add(m, params)
    if params[:channels].empty? || !@registry.has_key?(params[:mask])
      # if the channels parameter is omitted (meaning all channels), or the
      # hostmask isn't present in the registry, we just (over)write the channels
      # in the registry
      @registry[params[:mask]] = params[:channels].dup
      m.okay
    else
      # otherwise, merge the channels with the ones existing in the registry
      current_channels = @registry[params[:mask]]
      if current_channels.empty?
        m.reply "#{params[:mask]} is already being auto-opped on all channels"
      else
        # merge the already set channels
        @registry[params[:mask]] = (params[:channels] | current_channels).uniq
        m.okay
      end
    end
  end

  def rm(m, params)
    unless @registry.has_key?(params[:mask])
      m.reply @bot.lang.get('dunno')
      return
    end
    if (!params[:channels].empty? && @registry[params[:mask]] != nil)
      params[:channels].each do |c|
        @registry[params[:mask]] = @registry[params[:mask]].reject {|ele| ele =~ /^#{c}$/i}
      end
      if @registry[params[:mask]].empty?
        @registry.delete(params[:mask])
      end
    else
      @registry.delete(params[:mask])
    end
    m.okay
  end

  def list(m, params)
    debug @registry.length
    if(@registry.length > 0)
      @registry.each { |mask,channels|
        m.reply "#{mask} in #{channels.empty? ? 'all channels' : channels.join(', ')}"
      }
    else
      m.reply "No entries"
    end
  end
end

plugin = AutoOP.new

plugin.map 'autoop list', :action => 'list'
plugin.map 'autoop add :mask [*channels]', :action => 'add'
plugin.map 'autoop rm :mask [*channels]', :action => 'rm'
