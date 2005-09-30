# automatically lookup nicks in @registry and identify when asked

class NickServPlugin < Plugin
  
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
  end

  def password(m, params)
    @registry[params[:nick]] = params[:passwd]
    m.okay
  end
  def nick_register(m, params)
    passwd = params[:passwd] ? params[:passwd] : genpasswd
    message = "REGISTER #{passwd}"
    message += " #{params[:email]}" if params[:email]
    @bot.sendmsg "PRIVMSG", "NickServ", message
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
  def identify(m, params)
    if @registry.has_key?(@bot.nick)
      @bot.sendmsg "PRIVMSG", "NickServ", "IDENTIFY #{@registry[@bot.nick]}"
      m.okay
    else
      m.reply "I dunno the nickserv password for the nickname #{@bot.nick} :("
    end
  end
  
  def listen(m)
    return unless(m.kind_of? NoticeMessage)

    if (m.sourcenick == "NickServ" && m.message =~ /IDENTIFY/)
      debug "nickserv asked us to identify for nick #{@bot.nick}"
      if @registry.has_key?(@bot.nick)
        @bot.sendmsg "PRIVMSG", "NickServ", "IDENTIFY " + @registry[@bot.nick]
      end
    end
  end

end
plugin = NickServPlugin.new
plugin.map 'nickserv password :nick :passwd', :action => "password"
plugin.map 'nickserv register :passwd :email', :action => 'nick_register',
           :defaults => {:passwd => false, :email => false}
plugin.map 'nickserv listnicks', :action => "listnicks"
plugin.map 'nickserv identify', :action => "identify"
