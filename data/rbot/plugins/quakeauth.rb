# automatically auths with Q on quakenet servers

class QPlugin < Plugin
  
  def help(plugin, topic="")
    case topic
    when ""
      return "quath plugin: handles Q auths. topics set, identify"
    when "set"
      return "nickserv set <user> <passwd>: set the Q user and password and use it to identify in future"
    when "identify"
      return "quath identify: identify with Q (if user and auth are set)"
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

  def set(m, params)
    @registry['quakenet.user'] = params[:nick]
    @registry['quakenet.auth'] = params[:passwd]
    m.okay
  end
  
  def connect
    identify(nil, nil)
  end
  def identify(m, params)
    if @registry.has_key?('quakenet.user') && @registry.has_key?('quakenet.auth')
      debug "authing with Q using  #{@registry['quakenet.user']} #{@registry['quakenet.auth']}"
      @bot.sendmsg "PRIVMSG", "Q@CServe.quakenet.org", "auth #{@registry['quakenet.user']} #{@registry['quakenet.auth']}"                                                    
      m.okay if m
    else
      m.reply "not configured, try 'qauth set :nick :passwd'" if m
    end
  end

end
plugin = QPlugin.new
plugin.map 'qauth set :nick :passwd', :action => "set"
plugin.map 'qauth identify', :action => "identify"
