class OpPlugin < Plugin

  def help(plugin, topic="")
    return "op [<user>] [<channel>] => grant <user> (if ommitted yourself) ops in <channel> (or in the current channel if no channel is specified)"
  end

  def op(m, params)
    channel = params[:channel]
    user = params[:user]
    unless channel
      if m.private?
        target = user.nil? ? "you" : user 
        m.reply "You should tell me where you want me to op #{target}."
        return
      else
        channel = m.channel.to_s
      end
    end
    unless user
      user = m.sourcenick
    end

    m.okay unless channel == m.channel.to_s
    @bot.sendq("MODE #{channel} +o #{user}")
  end

  def opme(m, params)
    params[:user] = m.sourcenick
    op(m, params)
  end

end

plugin = OpPlugin.new
plugin.map("op [:user] [:channel]")
plugin.map("opme [:channel]") # For backwards compatibility with 0.9.10
plugin.default_auth("*",false)

