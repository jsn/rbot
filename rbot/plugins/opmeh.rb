class OpMehPlugin < Plugin

  def help(plugin, topic="")
    return "opmeh <channel> => grant user ops in <channel>"
  end

  def privmsg(m)
    unless(m.params)
      m.reply "usage: " + help(m.plugin)
      return
    end
    target = m.sourcenick
    channel = m.params
    @bot.sendq("MODE #{channel} +o #{target}")
  end
end
plugin = OpMehPlugin.new
plugin.register("opmeh")
