#-- vim:sw=2:et
#++


class Core < CoreBotModule

  # TODO cleanup
  # handle incoming IRC PRIVMSG +m+
  def listen(m)
    return unless m.class <= PrivMessage
    if(m.private? && m.message =~ /^\001PING\s+(.+)\001/)
      @bot.notice m.sourcenick, "\001PING #$1\001"
      @bot.irclog "@ #{m.sourcenick} pinged me"
      return
    end

    if(m.address?)
      case m.message
      when (/^join\s+(\S+)\s+(\S+)$/i)
        @bot.join $1, $2 if(@bot.auth.allow?("join", m.source, m.replyto))
      when (/^join\s+(\S+)$/i)
        @bot.join $1 if(@bot.auth.allow?("join", m.source, m.replyto))
      when (/^part$/i)
        @bot.part m.target if(m.public? && @bot.auth.allow?("join", m.source, m.replyto))
      when (/^part\s+(\S+)$/i)
        @bot.part $1 if(@bot.auth.allow?("join", m.source, m.replyto))
      when (/^quit(?:\s+(.*))?$/i)
        @bot.quit $1 if(@bot.auth.allow?("quit", m.source, m.replyto))
      when (/^restart(?:\s+(.*))?$/i)
        @bot.restart $1 if(@bot.auth.allow?("quit", m.source, m.replyto))
      when (/^hide$/i)
        @bot.join 0 if(@bot.auth.allow?("join", m.source, m.replyto))
      when (/^save$/i)
        if(@bot.auth.allow?("config", m.source, m.replyto))
          @bot.save
          m.okay
        end
      when (/^nick\s+(\S+)$/i)
        @bot.nickchg($1) if(@bot.auth.allow?("nick", m.source, m.replyto))
      when (/^say\s+(\S+)\s+(.*)$/i)
        @bot.say $1, $2 if(@bot.auth.allow?("say", m.source, m.replyto))
      when (/^action\s+(\S+)\s+(.*)$/i)
        @bot.action $1, $2 if(@bot.auth.allow?("say", m.source, m.replyto))
        # when (/^topic\s+(\S+)\s+(.*)$/i)
        #   topic $1, $2 if(@bot.auth.allow?("topic", m.source, m.replyto))
      when (/^mode\s+(\S+)\s+(\S+)\s+(.*)$/i)
        @bot.mode $1, $2, $3 if(@bot.auth.allow?("mode", m.source, m.replyto))
      when (/^ping$/i)
        @bot.say m.replyto, "pong"
      when (/^rescan$/i)
        if(@bot.auth.allow?("config", m.source, m.replyto))
          m.reply "saving ..."
          @bot.save
          m.reply "rescanning ..."
          @bot.rescan
          m.reply "done. #{@plugins.status(true)}"
        end
      when (/^quiet$/i)
        if(@bot.auth.allow?("talk", m.source, m.replyto))
          m.okay
          @bot.set_quiet
        end
      when (/^quiet in (\S+)$/i)
        where = $1
        if(@bot.auth.allow?("talk", m.source, m.replyto))
          m.okay
          where.gsub!(/^here$/, m.target) if m.public?
          @bot.set_quiet(where)
        end
      when (/^talk$/i)
        if(@bot.auth.allow?("talk", m.source, m.replyto))
          @bot.reset_quiet
          m.okay
        end
      when (/^talk in (\S+)$/i)
        where = $1
        if(@bot.auth.allow?("talk", m.source, m.replyto))
          where.gsub!(/^here$/, m.target) if m.public?
          @bot.reset_quiet(where)
          m.okay
        end
      when (/^status\??$/i)
        m.reply status if @bot.auth.allow?("status", m.source, m.replyto)
      when (/^registry stats$/i)
        if @bot.auth.allow?("config", m.source, m.replyto)
          m.reply @registry.stat.inspect
        end
      when (/^(help\s+)?config(\s+|$)/)
        @config.privmsg(m)
      when (/^(version)|(introduce yourself)$/i)
        @bot.say m.replyto, "I'm a v. #{$version} rubybot, (c) Tom Gilbert - http://linuxbrit.co.uk/rbot/"
      when (/^help(?:\s+(.*))?$/i)
        @bot.say m.replyto, help($1)
        #TODO move these to a "chatback" plugin
      when (/^(botsnack|ciggie)$/i)
        @bot.say m.replyto, @lang.get("thanks_X") % m.sourcenick if(m.public?)
        @bot.say m.replyto, @lang.get("thanks") if(m.private?)
      when (/^(hello|howdy|hola|salut|bonjour|sup|niihau|hey|hi(\W|$)|yo(\W|$)).*/i)
        @bot.say m.replyto, @lang.get("hello_X") % m.sourcenick if(m.public?)
        @bot.say m.replyto, @lang.get("hello") if(m.private?)
      end
    else
      # stuff to handle when not addressed
      case m.message
      when (/^\s*(hello|howdy|hola|salut|bonjour|sup|niihau|hey|hi|yo(\W|$))[\s,-.]+#{Regexp.escape(@bot.nick)}$/i)
        @bot.say m.replyto, @lang.get("hello_X") % m.sourcenick
      when (/^#{Regexp.escape(@bot.nick)}!*$/)
        @bot.say m.replyto, @lang.get("hello_X") % m.sourcenick
      else
        # @keywords.privmsg(m)
      end
    end
  end

  # handle help requests for "core" topics
  def help(topic="")
    case topic
    when "quit"
      return "quit [<message>] => quit IRC with message <message>"
    when "restart"
      return "restart => completely stop and restart the bot (including reconnect)"
    when "join"
      return "join <channel> [<key>] => join channel <channel> with secret key <key> if specified. #{myself} also responds to invites if you have the required access level"
    when "part"
      return "part <channel> => part channel <channel>"
    when "hide"
      return "hide => part all channels"
    when "save"
      return "save => save current dynamic data and configuration"
    when "rescan"
      return "rescan => reload modules and static facts"
    when "nick"
      return "nick <nick> => attempt to change nick to <nick>"
    when "say"
      return "say <channel>|<nick> <message> => say <message> to <channel> or in private message to <nick>"
    when "action"
      return "action <channel>|<nick> <message> => does a /me <message> to <channel> or in private message to <nick>"
    when "quiet"
      return "quiet [in here|<channel>] => with no arguments, stop speaking in all channels, if \"in here\", stop speaking in this channel, or stop speaking in <channel>"
    when "talk"
      return "talk [in here|<channel>] => with no arguments, resume speaking in all channels, if \"in here\", resume speaking in this channel, or resume speaking in <channel>"
    when "version"
      return "version => describes software version"
    when "botsnack"
      return "botsnack => reward #{myself} for being good"
    when "hello"
      return "hello|hi|hey|yo [#{myself}] => greet the bot"
    else
      return "Core help topics: quit, restart, config, join, part, hide, save, rescan, nick, say, action, topic, quiet, talk, version, botsnack, hello"
    end
  end
end

core = Core.new

