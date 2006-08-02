#-- vim:sw=2:et
#++


class Core < CoreBotModule

  def listen(m)
    return unless m.class <= PrivMessage
    if(m.private? && m.message =~ /^\001PING\s+(.+)\001/)
      @bot.notice m.sourcenick, "\001PING #$1\001"
      @bot.irclog "@ #{m.sourcenick} pinged me"
      return
    end
  end

  def bot_join(m, param)
    if param[:pass]
      @bot.join param[:chan], param[:pass]
    else
      @bot.join param[:chan]
    end
  end

  def bot_part(m, param)
    if param[:chan]
      @bot.part param[:chan]
    else
      @bot.part m.target if m.public?
    end
  end

  def bot_quit(m, param)
    @bot.quit(param[:msg] ? param[:msg].join(" ") : nil)
  end

  def bot_restart(m, param)
    @bot.restart(param[:msg] ? param[:msg].join(" ") : nil)
  end

  def bot_hide(m, param)
    @bot.join 0
  end

  def bot_save(m, param)
    @bot.save
    m.okay
  end

  def bot_nick(m, param)
    @bot.nickchg(param[:nick])
  end

  def bot_say(m, param)
    @bot.say param[:where], param[:what].join(" ")
  end

  def bot_action(m, param)
    @bot.action param[:where], param[:what].join(" ")
  end

  def bot_mode(m, param)
    @bot.mode param[:where], param[:what], param[:who].join(" ")
  end

  def bot_ping(m, param)
    m.reply "pong"
  end

  def bot_rescan(m, param)
    m.reply "saving ..."
    @bot.save
    m.reply "rescanning ..."
    @bot.rescan
    m.reply "done. #{@plugins.status(true)}"
  end

  def bot_quiet(m, param)
    if param.has_key?(:where)
      @bot.set_quiet param[:where].sub(/^here$/, m.target)
    else
      @bot.set_quiet
    end
  end

  def bot_talk(m, param)
    if param.has_key?(:where)
      @bot.reset_quiet param[:where].sub(/^here$/, m.target)
    else
      @bot.reset_quiet
    end
  end

  def bot_status(m, param)
    m.reply @bot.status
  end

  # TODO is this one of the methods that disappeared when the bot was moved
  # from the single-file to the multi-file registry?
  #
  #  def bot_reg_stat(m, param)
  #    m.reply @registry.stat.inspect
  #  end

  def bot_version(m, param)
    m.reply  "I'm a v. #{$version} rubybot, (c) Tom Gilbert - http://linuxbrit.co.uk/rbot/"
  end

  def bot_help(m, param)
    m.reply @bot.help(param[:topic].join(" "))
  end

  #TODO move these to a "chatback" plugin
  # when (/^(botsnack|ciggie)$/i)
  #   @bot.say m.replyto, @lang.get("thanks_X") % m.sourcenick if(m.public?)
  #   @bot.say m.replyto, @lang.get("thanks") if(m.private?)
  # when (/^(hello|howdy|hola|salut|bonjour|sup|niihau|hey|hi(\W|$)|yo(\W|$)).*/i)
  #   @bot.say m.replyto, @lang.get("hello_X") % m.sourcenick if(m.public?)
  #   @bot.say m.replyto, @lang.get("hello") if(m.private?)
  # when (/^\s*(hello|howdy|hola|salut|bonjour|sup|niihau|hey|hi|yo(\W|$))[\s,-.]+#{Regexp.escape(@bot.nick)}$/i)
  #   @bot.say m.replyto, @lang.get("hello_X") % m.sourcenick
  # when (/^#{Regexp.escape(@bot.nick)}!*$/)
  #   @bot.say m.replyto, @lang.get("hello_X") % m.sourcenick

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
      #     when "botsnack"
      #       return "botsnack => reward #{myself} for being good"
      #     when "hello"
      #       return "hello|hi|hey|yo [#{myself}] => greet the bot"
    else
      return "Core help topics: quit, restart, config, join, part, hide, save, rescan, nick, say, action, topic, quiet, talk, version, botsnack, hello"
    end
  end
end

core = Core.new

core.map "quit *msg",
  :action => 'bot_quit',
  :defaults => { :msg => nil },
  :auth => 'core::quit::quit'
core.map "restart *msg",
  :action => 'bot_restart',
  :defaults => { :msg => nil },
  :auth => 'core::quit::restart'

core.map "save",
  :action => 'bot_save',
  :auth => 'core::config::save'
core.map "rescan",
  :action => 'bot_rescan',
  :auth => 'core::config::rescan'
core.map "nick :nick",
  :action => 'bot_nick',
  :auth => 'core::config::nick'
core.map "status",
  :action => 'bot_status',
  :auth => 'core::config::show::status'
  # TODO see above
  #
  # core.map "registry stats",
  #   :action => 'bot_reg_stat',
  #   :auth => 'core::config::show::registry'
core.map "version",
  :action => 'bot_version',
  :auth => 'core::config::show::version'

core.map "quiet",
  :action => 'bot_quiet',
  :auth => 'core::talk::quiet'
core.map "quiet in :chan",
  :action => 'bot_quiet',
  :auth => 'core::talk::quiet'
core.map "talk",
  :action => 'bot_talk',
  :auth => 'core::talk::talk'
core.map "quiet in :chan",
  :action => 'bot_quiet',
  :auth => 'core::talk::talk'

core.map "join :chan :pass", 
  :action => 'bot_join',
  :defaults => {:pass => nil},
  :auth => 'core::movearound::join'
core.map "part :chan",
  :action => 'bot_part',
  :defaults => {:chan => nil},
  :auth => 'core::movearound::part'
core.map "hide",
  :action => 'bot_hide',
  :auth => 'core::movearound::hide'

core.map "say :where *what",
  :action => 'bot_say',
  :auth => 'core::talk::say'
core.map "action :where *what",
  :action => 'bot_action',
  :auth => 'core::talk::act'
core.map "mode :where :what *who",
  :action => 'bot_mode',
  :auth => 'core::talk::mode'

core.map "ping",
  :action => 'bot_ping'
core.map "help *topic",
  :action => 'bot_help',
  :default => { :topic => [""] }

# TODO the first line should probably go to the auth module?
#
core.default_auth('*', true)
core.default_auth('core', false)
core.default_auth('core::config::show', true)

