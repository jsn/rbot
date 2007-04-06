class RiPlugin < Plugin

  BotConfig.register BotConfigIntegerValue.new('ri.max_length',
    :default => 512,
    :desc => "Maximum length of ri entry (in bytes) which is ok to be sent to channels")


  RI_COMMAND = %w{ri -f simple -T}

  def help(plugin, topic="")
    "ri <something> => returns ruby documentation for <something>"
  end
  def ri(m, params)
    args = RI_COMMAND.dup
    if a = params[:something]
      if a == '-c'
        args.push(a)
      else
        args.push('--')
        args.push(a)
      end
    end
    begin
      ret = Utils.safe_exec(*args)
    rescue
      ret = "failed to execute ri"
    end
    ret = ret.gsub(/\t/, "  ").split(/\n/).join(" ").gsub(/\s\s+/, '  ')
    
    if ret.length > @bot.config['ri.max_length'] && !m.private?
      ret = 'entry is too long to send to the channel, use /msg to ask me about it'
    end
    m.reply(ret)
    return
  end
end
plugin = RiPlugin.new
plugin.map 'ri :something',
  :requirements => {:something => /^((-c)|(\w\S+))$/}
