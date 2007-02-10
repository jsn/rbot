class OpPlugin < Plugin

  def help(plugin, topic="")
    return "'op [<user>] [<channel>]' => grant user> (if ommitted yourself) ops in <channel> (or in the current channel if no channel is specified). Use deop instead of op to remove the privilege."
  end

  def op(m, params)
    channel = params[:channel]
    user = params[:user]
    do_mode(m, channel, user, "+o")
  end

  def opme(m, params)
    params[:user] = m.sourcenick
    op(m, params)
  end

  def deop(m, params)
    channel = params[:channel]
    user = params[:user]
    do_mode(m, channel, user, "-o")
  end

  def deopme(m, params)
    params[:user] = m.sourcenick
    deop(m, params)
  end

  def hop(m, params)
    channel = params[:channel]
    user = params[:user]
    do_mode(m, channel, user, "+h")
  end

  def hopme(m, params)
    params[:user] = m.sourcenick
    hop(m, params)
  end

  def dehop(m, params)
    channel = params[:channel]
    user = params[:user]
    do_mode(m, channel, user, "-h")
  end

  def dehopme(m, params)
    params[:user] = m.sourcenick
    dehop(m, params)
  end

  def voice(m, params)
    channel = params[:channel]
    user = params[:user]
    do_mode(m, channel, user, "+v")
  end

  def voiceme(m, params)
    params[:user] = m.sourcenick
    voice(m, params)
  end

  def devoice(m, params)
    channel = params[:channel]
    user = params[:user]
    do_mode(m, channel, user, "-v")
  end

  def devoiceme(m, params)
    params[:user] = m.sourcenick
    deop(m, params)
  end

  def do_mode(m, channel, user, mode)
    unless channel
      if m.private?
        target = user.nil? ? "you" : user 
        m.reply "You should tell me where you want me to #{mode} #{target}."
        return
      else
        channel = m.channel
      end
    else
      channel = m.server.channel(channel)

      unless channel.has_user?(@bot.nick)
        m.reply "I am not in that channel"
	return
      end
    end

    unless user
      user = m.sourcenick
    end

    m.okay unless channel == m.channel.to_s
    @bot.mode(channel, mode, user)
  end
end

plugin = OpPlugin.new
plugin.map("op [:user] [:channel]")
plugin.map("opme [:channel]") # For backwards compatibility with 0.9.10
plugin.map("deop [:user] [:channel]")
plugin.map("deopme [:channel]") # For backwards compatibility with 0.9.10
plugin.map("hop [:user] [:channel]")
plugin.map("hopme [:channel]")
plugin.map("dehop [:user] [:channel]")
plugin.map("dehopme [:channel]")
plugin.map("voice [:user] [:channel]")
plugin.map("voiceme [:channel]")
plugin.map("devoice [:user] [:channel]")
plugin.map("devoiceme [:channel]")
plugin.default_auth("*",false)

