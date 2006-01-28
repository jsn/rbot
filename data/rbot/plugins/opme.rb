class OpMePlugin < Plugin

  def help(plugin, topic="")
    return "opme <channel> => grant user ops in <channel>"
  end

  def privmsg(m)
    if(m.params)
      channel = m.params
    else
      channel = m.channel
    end
    target = m.sourcenick
    m.okay
    @bot.sendq("MODE #{channel} +o #{target}")
  end
end
plugin = OpMePlugin.new
plugin.register("opme")
