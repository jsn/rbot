# automatically lookup nicks in @registry and identify when asked

class NickServPlugin < Plugin
  
  def help(plugin, topic="")
    case topic
    when ""
      return "nickserv plugin: handles nickserv protected IRC nicks. topics password, register, identify, listnicks"
    when "password"
      return "nickserv password <nick> <passwd>: remember the password for nick <nick> and use it to identify in future"
    when "register"
      return "nickserv register [<password>]: register the current nick, choosing a random password unless <password> is supplied - current nick must not already be registered for this to work"
    when "identify"
      return "nickserv identify: identify with nickserv - shouldn't be needed - bot should identify with nickserv immediately on request - however this could be useful after splits or service disruptions, or when you just set the password for the current nick"
    when "listnicks"
      return "nickserv listnicks: lists nicknames and associated password the bot knows about - you will need config level auth access to do this one and it will reply by privmsg only"
    end
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
  
  def privmsg(m)
    return unless m.params
    
    case m.params
    when (/^password\s*(\S*)\s*(.*)$/)
      nick = $1
      passwd = $2
      @registry[nick] = passwd
      @bot.okay m.replyto
    when (/^register$/)
      passwd = genpasswd
      @bot.sendmsg "PRIVMSG", "NickServ", "REGISTER " + passwd
      @registry[@bot.nick] = passwd
      @bot.okay m.replyto
    when (/^register\s*(.*)\s*$/)
      passwd = $1
      @bot.sendmsg "PRIVMSG", "NickServ", "REGISTER " + passwd
      @registry[@bot.nick] = passwd
      @bot.okay m.replyto
    when (/^listnicks$/)
      if @bot.auth.allow?("config", m.source, m.replyto)
        if @registry.length > 0
          @registry.each {|k,v|
            @bot.say m.sourcenick, "#{k} => #{v}"
          }
        else
          m.reply "none known"
        end
      end
    when (/^identify$/)
      if @registry.has_key?(@bot.nick)
        @bot.sendmsg "PRIVMSG", "NickServ", "IDENTIFY " + @registry[@bot.nick]
        @bot.okay m.replyto
      else
        m.reply "I dunno the nickserv password for the nickname #{@bot.nick} :("
      end
    end
  end
  
  def listen(m)
    return unless(m.kind_of? NoticeMessage)

    if (m.sourcenick == "NickServ" && m.message =~ /This nickname is owned by someone else/)
      puts "nickserv asked us to identify for nick #{@bot.nick}"
      if @registry.has_key?(@bot.nick)
        @bot.sendmsg "PRIVMSG", "NickServ", "IDENTIFY " + @registry[@bot.nick]
      end
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
end
plugin = NickServPlugin.new
plugin.register("nickserv")
