class OpMePlugin < Plugin

  def help(plugin, topic="")
    return "opme [<channel>] => grant user ops in <channel> (or in the current channel if no channel is specified)"
  end

  def opme(m, params)
    channel = params[:chan]
    unless channel
      if m.private?
        m.reply "you should tell me where you want me to op you"
        return
      else
        channel = m.channel.to_s
      end
    end
    target = m.sourcenick
    m.okay unless channel == m.channel.to_s
    @bot.sendq("MODE #{channel} +o #{target}")
  end
end

plugin = OpMePlugin.new
plugin.map("opme [:chan]")
plugin.default_auth("*",false)
