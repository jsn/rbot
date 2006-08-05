#-- vim:sw=2:et
#++


class BasicsModule < CoreBotModule

  def listen(m)
    return unless m.kind_of?(PrivMessage)
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
  def help(plugin, topic="")
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
      return "#{name}: quit, restart, join, part, hide, save, rescan, nick, say, action, topic, quiet, talk, version"#, botsnack, hello"
    end
  end
end

basics = BasicsModule.new

basics.map "quit *msg",
  :action => 'bot_quit',
  :defaults => { :msg => nil },
  :auth_path => 'quit'
basics.map "restart *msg",
  :action => 'bot_restart',
  :defaults => { :msg => nil },
  :auth_path => 'quit'

basics.map "quiet",
  :action => 'bot_quiet',
  :auth_path => 'talk::set'
basics.map "quiet in :chan",
  :action => 'bot_quiet',
  :auth_path => 'talk::set'
basics.map "talk",
  :action => 'bot_talk',
  :auth_path => 'talk::set'
basics.map "quiet in :chan",
  :action => 'bot_quiet',
  :auth_path => 'talk::set'

basics.map "say :where *what",
  :action => 'bot_say',
  :auth_path => 'talk::do'
basics.map "action :where *what",
  :action => 'bot_action',
  :auth_path => 'talk::do'
basics.map "mode :where :what *who",
  :action => 'bot_mode',
  :auth_path => 'talk::do'

basics.map "join :chan :pass", 
  :action => 'bot_join',
  :defaults => {:pass => nil},
  :auth_path => 'move'
basics.map "part :chan",
  :action => 'bot_part',
  :defaults => {:chan => nil},
  :auth_path => 'move'
basics.map "hide",
  :action => 'bot_hide',
  :auth_path => 'move'

basics.map "ping",
  :action => 'bot_ping',
  :auth_path => '!ping!'
basics.map "help *topic",
  :action => 'bot_help',
  :default => { :topic => [""] },
  :auth_path => '!help!'

basics.default_auth('*', false)

