# Automatically lookup nicks in @registry and identify when asked
# Takes over proper nick if required and nick is registered
# TODO allow custom IDENTIFY and GHOST names

class NickServPlugin < Plugin
  
  BotConfig.register BotConfigStringValue.new('nickserv.name',
    :default => "nickserv", :requires_restart => false,
    :desc => "Name of the nick server (all lowercase)")
  BotConfig.register BotConfigStringValue.new('nickserv.ident_request',
    :default => "IDENTIFY", :requires_restart => false,
    :on_change => Proc.new { |bot, v| bot.plugins.delegate "set_ident_request", v },
    :desc => "String to look for to see if the nick server is asking us to identify")
  BotConfig.register BotConfigStringValue.new('nickserv.nick_avail',
    :default => "not (currently )?online|killed|recovered|disconnesso|libero",
    :requires_restart => false,
    :on_change => Proc.new { |bot, v| bot.plugins.delegate "set_nick_avail", v },
    :desc => "String to look for to see if the nick server is informing us that our nick is now available")
  BotConfig.register BotConfigBooleanValue.new('nickserv.wants_nick',
    :default => false, :requires_restart => false,
    :desc => "Set to false if the nick server doesn't expect the nick as a parameter in the identify command")
  BotConfig.register BotConfigIntegerValue.new('nickserv.wait',
    :default => 30, :validate => Proc.new { |v| v > 0 }, :requires_restart => false,
    :desc => "Seconds to wait after sending a message to nickserv, e.g. after ghosting")

  def help(plugin, topic="")
    case topic
    when ""
      return "nickserv plugin: handles nickserv protected IRC nicks. topics password, register, identify, listnicks"
    when "password"
      return "nickserv password [<nick>] <passwd>: remember the password for nick <nick> and use it to identify in future"
    when "register"
      return "nickserv register [<password> [<email>]]: register the current nick, choosing a random password unless <password> is supplied - current nick must not already be registered for this to work. Also specify email if required by your services"
    when "identify"
      return "nickserv identify: identify with nickserv - shouldn't be needed - bot should identify with nickserv immediately on request - however this could be useful after splits or service disruptions, or when you just set the password for the current nick"
    when "listnicks"
      return "nickserv listnicks: lists nicknames and associated password the bot knows about - you will need config level auth access to do this one and it will reply by privmsg only"
    end
  end
  
  def genpasswd
    return Irc::Auth.random_password
  end

  def set_ident_request(val)
    @ident_request = Regexp.new(val)
  end

  def set_nick_avail(val)
    @nick_avail = Regexp.new(val)
  end

  def initialize
    super
    # this plugin only wants to store strings!
    class << @registry
      def store(val)
        val
      end
      def restore(val)
        val
      end
    end
    set_ident_request(@bot.config['nickserv.ident_request'])
    set_nick_avail(@bot.config['nickserv.nick_avail'])
  end

  # Returns the nickserv name
  def ns_nick
    @bot.config['nickserv.name']
  end

  # say something to nickserv
  def ns_say(msg)
    @bot.say ns_nick, msg
  end

  def password(m, params)
    nick = params[:nick] || @bot.nick
    passwd = params[:passwd]
    if nick == @bot.nick
      ns_say "SET PASSWORD #{passwd}"
    else
      m.reply "I'm only changing this in my database, I won't inform #{ns_nick} of the change"
    end
    @registry[nick] = passwd
    m.okay
  end

  def nick_register(m, params)
    passwd = params[:passwd] ? params[:passwd] : genpasswd
    message = "REGISTER #{passwd}"
    message += " #{params[:email]}" if params[:email]
    ns_say message
    @registry[@bot.nick] = passwd
    m.okay
  end

  def listnicks(m, params)
    if @registry.length > 0
      @registry.each {|k,v|
        @bot.say m.sourcenick, "#{k} => #{v}"
      }
    else
      m.reply "none known"
    end
  end

  def do_identify(nick=@bot.nick)
    if @registry.has_key?(nick)
      if @bot.config['nickserv.wants_nick']
        ns_say "IDENTIFY #{nick} #{@registry[nick]}"
      else
        if nick == @bot.nick
          ns_say "IDENTIFY #{@registry[nick]}"
        else
          # We cannot identify for different nicks if we can't use the nickname ...
          return false
        end
      end
      return true
    end
    return nil
  end

  def identify(m, params)
    ided = do_identify
    case ided
    when true
      m.okay
    when false
      m.reply "I cannot identify for a this nick"
    when nil
      m.reply "I dunno the nickserv password for the nickname #{@bot.nick} :("
    else
      m.reply "uh ... something went wrong ..."
    end
  end
  
  def connect
    do_identify
  end
  
  def nicktaken(nick)
    if @registry.has_key?(nick)
      ns_say "GHOST #{nick} #{@registry[nick]}"
    end
  end

  def listen(m)
    return unless(m.kind_of? NoticeMessage)
    return unless m.source.downcase == ns_nick.downcase

    case m.message
    when @ident_request
      debug "nickserv asked us to identify for nick #{@bot.nick}"
      do_identify
    when @nick_avail
      debug "our nick seems to be free now"
      @bot.nickchg @bot.config['irc.nick']
    end
  end

end
plugin = NickServPlugin.new
plugin.map 'nickserv password [:nick] :passwd', :action => "password"
plugin.map 'nickserv register :passwd :email', :action => 'nick_register',
           :defaults => {:passwd => false, :email => false}
plugin.map 'nickserv listnicks', :action => "listnicks"
plugin.map 'nickserv identify', :action => "identify"

plugin.default_auth('*', false)

