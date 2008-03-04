class OpMehPlugin < Plugin

  def help(plugin, topic="")
    return "opmeh <channel> => grant user ops in <channel>"
  end

  def privmsg(m)
    if(m.params)
      channel = m.params
    else
      channel = m.channel
    end
    target = m.sourcenick
    @bot.sendq("MODE #{channel} +o #{target}")
    m.okay
  end
end
plugin = OpMehPlugin.new
plugin.register("opmeh")
