# Automatically lookup nicks in @registry and identify when asked
# Takes over proper nick if required and nick is registered
# TODO allow custom IDENTIFY and GHOST names
# TODO instead of nickserv.wait it would be ideal if we could just
# set up "don't send further commands until you receive this particular message"

class NickServPlugin < Plugin
  
  BotConfig.register BotConfigStringValue.new('nickserv.name',
    :default => "NickServ", :requires_restart => false,
    :desc => "Name of the nick server")
  BotConfig.register BotConfigStringValue.new('nickserv.ident_request',
    :default => "IDENTIFY", :requires_restart => false,
    :on_change => Proc.new { |bot, v| bot.plugins.delegate "set_ident_request", v },
    :desc => "String to look for to see if the nick server is asking us to identify")
  BotConfig.register BotConfigBooleanValue.new('nickserv.wants_nick',
    :default => true, :requires_restart => false,
    :desc => "Set to false if the nick server doesn't expect the nick as a parameter in the identify command")
  BotConfig.register BotConfigIntegerValue.new('nickserv.wait',
    :default => 30, :validate => Proc.new { |v| v > 0 }, :requires_restart => false,
    :desc => "Seconds to wait after sending a message to nickserv, e.g. after ghosting")

  def help(plugin, topic="")
    case topic
    when ""
      return "nickserv plugin: handles nickserv protected IRC nicks. topics password, register, identify, listnicks"
    when "password"
      return "nickserv password <nick> <passwd>: remember the password for nick <nick> and use it to identify in future"
    when "register"
      return "nickserv register [<password> [<email>]]: register the current nick, choosing a random password unless <password> is supplied - current nick must not already be registered for this to work. Also specify email if required by your services"
    when "identify"
      return "nickserv identify: identify with nickserv - shouldn't be needed - bot should identify with nickserv immediately on request - however this could be useful after splits or service disruptions, or when you just set the password for the current nick"
    when "listnicks"
      return "nickserv listnicks: lists nicknames and associated password the bot knows about - you will need config level auth access to do this one and it will reply by privmsg only"
    end
  end
  
  def genpasswd
    # generate a random password
    passwd = ""
    8.times do
      passwd += (rand(26) + (rand(2) == 0 ? 65 : 97) ).chr
    end
    return passwd
  end

  def set_ident_request(val)
    @ident_request = Regexp.new(val)
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
  end

  def password(m, params)
    @registry[params[:nick]] = params[:passwd]
    m.okay
  end

  def nick_register(m, params)
    passwd = params[:passwd] ? params[:passwd] : genpasswd
    message = "REGISTER #{passwd}"
    message += " #{params[:email]}" if params[:email]
    @bot.sendmsg "PRIVMSG", @bot.config['nickserv.name'], message
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
        @bot.sendmsg "PRIVMSG", @bot.config['nickserv.name'], "IDENTIFY #{nick} #{@registry[nick]}"
      else
        if nick == @bot.nick
          @bot.sendmsg "PRIVMSG", @bot.config['nickserv.name'], "IDENTIFY #{@registry[nick]}"
        else
          # We cannot identify for different nicks if we can't use the nickname ...
          return false
        end
      end
      return true
    end
    return false
  end

  def identify(m, params)
    if do_identify
      m.okay
    else
      m.reply "I dunno the nickserv password for the nickname #{@bot.nick} :("
    end
  end
  
  def connect
    do_identify
  end
  
  def nicktaken(nick)
    if @registry.has_key?(nick)
      @bot.sendmsg "PRIVMSG", @bot.config['nickserv.name'], "GHOST #{nick} #{@registry[nick]}"
      if do_identify nick
        sleep @bot.config['nickserv.wait']
        @bot.nickchg nick
        # We need to wait after changing nick, otherwise the server
        # might refuse to execute further commangs, e.g. subsequent JOIN
        # commands until the nick has changed.
        sleep @bot.config['nickserv.wait']
      else
        debug "Failed to identify for nick #{nick}, cannot take over"
      end
    end
  end

  def listen(m)
    return unless(m.kind_of? NoticeMessage)

    if (m.sourcenick == @bot.config['nickserv.name'] && m.message =~ @ident_request)
      debug "nickserv asked us to identify for nick #{@bot.nick}"
      do_identify
    end
  end

end
plugin = NickServPlugin.new
plugin.map 'nickserv password :nick :passwd', :action => "password"
plugin.map 'nickserv register :passwd :email', :action => 'nick_register',
           :defaults => {:passwd => false, :email => false}
plugin.map 'nickserv listnicks', :action => "listnicks"
plugin.map 'nickserv identify', :action => "identify"
