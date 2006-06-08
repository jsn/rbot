require 'thread'
require 'etc'
require 'fileutils'

$debug = false unless $debug
# print +message+ if debugging is enabled
def debug(message=nil)
  stamp = Time.now.strftime("%Y/%m/%d %H:%M:%S")
  print "D: [#{stamp}] #{message}\n" if($debug && message)
  #yield
end

# these first
require 'rbot/rbotconfig'
require 'rbot/config'
require 'rbot/utils'

require 'rbot/rfc2812'
require 'rbot/keywords'
require 'rbot/ircsocket'
require 'rbot/auth'
require 'rbot/timer'
require 'rbot/plugins'
require 'rbot/channel'
require 'rbot/message'
require 'rbot/language'
require 'rbot/dbhash'
require 'rbot/registry'
require 'rbot/httputil'

module Irc

# Main bot class, which manages the various components, receives messages,
# handles them or passes them to plugins, and contains core functionality.
class IrcBot
  # the bot's current nickname
  attr_reader :nick
  
  # the bot's IrcAuth data
  attr_reader :auth
  
  # the bot's BotConfig data
  attr_reader :config
  
  # the botclass for this bot (determines configdir among other things)
  attr_reader :botclass
  
  # used to perform actions periodically (saves configuration once per minute
  # by default)
  attr_reader :timer
  
  # bot's Language data
  attr_reader :lang

  # channel info for channels the bot is in
  attr_reader :channels

  # bot's irc socket
  attr_reader :socket

  # bot's object registry, plugins get an interface to this for persistant
  # storage (hash interface tied to a bdb file, plugins use Accessors to store
  # and restore objects in their own namespaces.)
  attr_reader :registry

  # bot's httputil help object, for fetching resources via http. Sets up
  # proxies etc as defined by the bot configuration/environment
  attr_reader :httputil

  # create a new IrcBot with botclass +botclass+
  def initialize(botclass, params = {})
    # BotConfig for the core bot
    BotConfig.register BotConfigStringValue.new('server.name',
      :default => "localhost", :requires_restart => true,
      :desc => "What server should the bot connect to?",
      :wizard => true)
    BotConfig.register BotConfigIntegerValue.new('server.port',
      :default => 6667, :type => :integer, :requires_restart => true,
      :desc => "What port should the bot connect to?", 
      :validate => Proc.new {|v| v > 0}, :wizard => true)
    BotConfig.register BotConfigStringValue.new('server.password',
      :default => false, :requires_restart => true,
      :desc => "Password for connecting to this server (if required)",
      :wizard => true)
    BotConfig.register BotConfigStringValue.new('server.bindhost',
      :default => false, :requires_restart => true,
      :desc => "Specific local host or IP for the bot to bind to (if required)",
      :wizard => true)
    BotConfig.register BotConfigIntegerValue.new('server.reconnect_wait',
      :default => 5, :validate => Proc.new{|v| v >= 0},
      :desc => "Seconds to wait before attempting to reconnect, on disconnect")
    BotConfig.register BotConfigStringValue.new('irc.nick', :default => "rbot",
      :desc => "IRC nickname the bot should attempt to use", :wizard => true,
      :on_change => Proc.new{|bot, v| bot.sendq "NICK #{v}" })
    BotConfig.register BotConfigStringValue.new('irc.user', :default => "rbot",
      :requires_restart => true,
      :desc => "local user the bot should appear to be", :wizard => true)
    BotConfig.register BotConfigArrayValue.new('irc.join_channels',
      :default => [], :wizard => true,
      :desc => "What channels the bot should always join at startup. List multiple channels using commas to separate. If a channel requires a password, use a space after the channel name. e.g: '#chan1, #chan2, #secretchan secritpass, #chan3'")
    BotConfig.register BotConfigIntegerValue.new('core.save_every',
      :default => 60, :validate => Proc.new{|v| v >= 0},
      # TODO change timer via on_change proc
      :desc => "How often the bot should persist all configuration to disk (in case of a server crash, for example")
    BotConfig.register BotConfigFloatValue.new('server.sendq_delay',
      :default => 2.0, :validate => Proc.new{|v| v >= 0},
      :desc => "(flood prevention) the delay between sending messages to the server (in seconds)",
      :on_change => Proc.new {|bot, v| bot.socket.sendq_delay = v })
    BotConfig.register BotConfigIntegerValue.new('server.sendq_burst',
      :default => 4, :validate => Proc.new{|v| v >= 0},
      :desc => "(flood prevention) max lines to burst to the server before throttling. Most ircd's allow bursts of up 5 lines, with non-burst limits of 512 bytes/2 seconds",
      :on_change => Proc.new {|bot, v| bot.socket.sendq_burst = v })
    BotConfig.register BotConfigIntegerValue.new('server.ping_timeout',
      :default => 10, :validate => Proc.new{|v| v >= 0},
      :on_change => Proc.new {|bot, v| bot.start_server_pings},
      :desc => "reconnect if server doesn't respond to PING within this many seconds (set to 0 to disable)")

    @argv = params[:argv]

    unless FileTest.directory? Config::datadir
      puts "data directory '#{Config::datadir}' not found, did you setup.rb?"
      exit 2
    end
    
    botclass = "#{Etc.getpwuid(Process::Sys.geteuid)[:dir]}/.rbot" unless botclass
    #botclass = "#{ENV['HOME']}/.rbot" unless botclass
    @botclass = botclass.gsub(/\/$/, "")

    unless FileTest.directory? botclass
      puts "no #{botclass} directory found, creating from templates.."
      if FileTest.exist? botclass
        puts "Error: file #{botclass} exists but isn't a directory"
        exit 2
      end
      FileUtils.cp_r Config::datadir+'/templates', botclass
    end
    
    Dir.mkdir("#{botclass}/logs") unless File.exist?("#{botclass}/logs")

    @ping_timer = nil
    @pong_timer = nil
    @last_ping = nil
    @startup_time = Time.new
    @config = BotConfig.new(self)
# TODO background self after botconfig has a chance to run wizard
    @timer = Timer::Timer.new(1.0) # only need per-second granularity
    @registry = BotRegistry.new self
    @timer.add(@config['core.save_every']) { save } if @config['core.save_every']
    @channels = Hash.new
    @logs = Hash.new
    @httputil = Utils::HttpUtil.new(self)
    @lang = Language::Language.new(@config['core.language'])
    @keywords = Keywords.new(self)
    @auth = IrcAuth.new(self)

    Dir.mkdir("#{botclass}/plugins") unless File.exist?("#{botclass}/plugins")
    @plugins = Plugins::Plugins.new(self, ["#{botclass}/plugins"])

    @socket = IrcSocket.new(@config['server.name'], @config['server.port'], @config['server.bindhost'], @config['server.sendq_delay'], @config['server.sendq_burst'])
    @nick = @config['irc.nick']

    @client = IrcClient.new
    @client[:privmsg] = proc { |data|
      message = PrivMessage.new(self, data[:source], data[:target], data[:message])
      onprivmsg(message)
    }
    @client[:notice] = proc { |data|
      message = NoticeMessage.new(self, data[:source], data[:target], data[:message])
      # pass it off to plugins that want to hear everything
      @plugins.delegate "listen", message
    }
    @client[:motd] = proc { |data|
      data[:motd].each_line { |line|
        log "MOTD: #{line}", "server"
      }
    }
    @client[:nicktaken] = proc { |data| 
      nickchg "#{data[:nick]}_"
    }
    @client[:badnick] = proc {|data| 
      puts "WARNING, bad nick (#{data[:nick]})"
    }
    @client[:ping] = proc {|data|
      # (jump the queue for pongs)
      @socket.puts "PONG #{data[:pingid]}"
    }
    @client[:pong] = proc {|data|
      @last_ping = nil
    }
    @client[:nick] = proc {|data|
      sourcenick = data[:sourcenick]
      nick = data[:nick]
      m = NickMessage.new(self, data[:source], data[:sourcenick], data[:nick])
      if(sourcenick == @nick)
        debug "my nick is now #{nick}"
        @nick = nick
      end
      @channels.each {|k,v|
        if(v.users.has_key?(sourcenick))
          log "@ #{sourcenick} is now known as #{nick}", k
          v.users[nick] = v.users[sourcenick]
          v.users.delete(sourcenick)
        end
      }
      @plugins.delegate("listen", m)
      @plugins.delegate("nick", m)
    }
    @client[:quit] = proc {|data|
      source = data[:source]
      sourcenick = data[:sourcenick]
      sourceurl = data[:sourceaddress]
      message = data[:message]
      m = QuitMessage.new(self, data[:source], data[:sourcenick], data[:message])
      if(data[:sourcenick] =~ /#{Regexp.escape(@nick)}/i)
      else
        @channels.each {|k,v|
          if(v.users.has_key?(sourcenick))
            log "@ Quit: #{sourcenick}: #{message}", k
            v.users.delete(sourcenick)
          end
        }
      end
      @plugins.delegate("listen", m)
      @plugins.delegate("quit", m)
    }
    @client[:mode] = proc {|data|
      source = data[:source]
      sourcenick = data[:sourcenick]
      sourceurl = data[:sourceaddress]
      channel = data[:channel]
      targets = data[:targets]
      modestring = data[:modestring]
      log "@ Mode #{modestring} #{targets} by #{sourcenick}", channel
    }
    @client[:welcome] = proc {|data|
      log "joined server #{data[:source]} as #{data[:nick]}", "server"
      debug "I think my nick is #{@nick}, server thinks #{data[:nick]}"
      if data[:nick] && data[:nick].length > 0
        @nick = data[:nick]
      end

      @plugins.delegate("connect")

      @config['irc.join_channels'].each {|c|
        debug "autojoining channel #{c}"
        if(c =~ /^(\S+)\s+(\S+)$/i)
          join $1, $2
        else
          join c if(c)
        end
      }
    }
    @client[:join] = proc {|data|
      m = JoinMessage.new(self, data[:source], data[:channel], data[:message])
      onjoin(m)
    }
    @client[:part] = proc {|data|
      m = PartMessage.new(self, data[:source], data[:channel], data[:message])
      onpart(m)
    }
    @client[:kick] = proc {|data|
      m = KickMessage.new(self, data[:source], data[:target],data[:channel],data[:message]) 
      onkick(m)
    }
    @client[:invite] = proc {|data|
      if(data[:target] =~ /^#{Regexp.escape(@nick)}$/i)
        join data[:channel] if (@auth.allow?("join", data[:source], data[:sourcenick]))
      end
    }
    @client[:changetopic] = proc {|data|
      channel = data[:channel]
      sourcenick = data[:sourcenick]
      topic = data[:topic]
      timestamp = data[:unixtime] || Time.now.to_i
      if(sourcenick == @nick)
        log "@ I set topic \"#{topic}\"", channel
      else
        log "@ #{sourcenick} set topic \"#{topic}\"", channel
      end
      m = TopicMessage.new(self, data[:source], data[:channel], timestamp, data[:topic])

      ontopic(m)
      @plugins.delegate("listen", m)
      @plugins.delegate("topic", m)
    }
    @client[:topic] = @client[:topicinfo] = proc {|data|
      channel = data[:channel]
      m = TopicMessage.new(self, data[:source], data[:channel], data[:unixtime], data[:topic])
        ontopic(m)
    }
    @client[:names] = proc {|data|
      channel = data[:channel]
      users = data[:users]
      unless(@channels[channel])
        puts "bug: got names for channel '#{channel}' I didn't think I was in\n"
        exit 2
      end
      @channels[channel].users.clear
      users.each {|u|
        @channels[channel].users[u[0].sub(/^[@&~+]/, '')] = ["mode", u[1]]
      }
    }
    @client[:unknown] = proc {|data|
      #debug "UNKNOWN: #{data[:serverstring]}"
      log data[:serverstring], ".unknown"
    }
  end

  # connect the bot to IRC
  def connect
    begin
      trap("SIGINT") { quit }
      trap("SIGTERM") { quit }
      trap("SIGHUP") { quit }
    rescue
      debug "failed to trap signals, probably running on windows?"
    end
    begin
      @socket.connect
    rescue => e
      raise "failed to connect to IRC server at #{@config['server.name']} #{@config['server.port']}: " + e
    end
    @socket.puts "PASS " + @config['server.password'] if @config['server.password']
    @socket.puts "NICK #{@nick}\nUSER #{@config['irc.user']} 4 #{@config['server.name']} :Ruby bot. (c) Tom Gilbert"
    start_server_pings
  end

  # begin event handling loop
  def mainloop
    while true
      begin
        connect
        @timer.start
      
        while true
          if @socket.select
            break unless reply = @socket.gets
            @client.process reply
          end
        end
      # I despair of this. Some of my users get "connection reset by peer"
      # exceptions that ARENT SocketError's. How am I supposed to handle
      # that?
      #rescue TimeoutError, SocketError => e
      rescue SystemExit
        exit 0
      rescue Exception => e
        puts "network exception: connection closed: #{e.inspect}"
        puts e.backtrace.join("\n")
        @socket.shutdown # now we reconnect
      rescue => e
        puts "unexpected exception: connection closed: #{e.inspect}"
        puts e.backtrace.join("\n")
        exit 2
      end
      
      puts "disconnected"
      @last_ping = nil
      @channels.clear
      @socket.clearq
      
      puts "waiting to reconnect"
      sleep @config['server.reconnect_wait']
    end
  end
  
  # type:: message type
  # where:: message target
  # message:: message text
  # send message +message+ of type +type+ to target +where+
  # Type can be PRIVMSG, NOTICE, etc, but those you should really use the
  # relevant say() or notice() methods. This one should be used for IRCd
  # extensions you want to use in modules.
  def sendmsg(type, where, message)
    # limit it 440 chars + CRLF.. so we have to split long lines
    left = 440 - type.length - where.length - 3
    begin
      if(left >= message.length)
        sendq("#{type} #{where} :#{message}")
        log_sent(type, where, message)
        return
      end
      line = message.slice!(0, left)
      lastspace = line.rindex(/\s+/)
      if(lastspace)
        message = line.slice!(lastspace, line.length) + message
        message.gsub!(/^\s+/, "")
      end
      sendq("#{type} #{where} :#{line}")
      log_sent(type, where, line)
    end while(message.length > 0)
  end

  # queue an arbitraty message for the server
  def sendq(message="")
    # temporary
    @socket.queue(message)
  end

  # send a notice message to channel/nick +where+
  def notice(where, message)
    message.each_line { |line|
      line.chomp!
      next unless(line.length > 0)
      sendmsg("NOTICE", where, line)
    }
  end

  # say something (PRIVMSG) to channel/nick +where+
  def say(where, message)
    message.to_s.gsub(/[\r\n]+/, "\n").each_line { |line|
      line.chomp!
      next unless(line.length > 0)
      unless((where =~ /^#/) && (@channels.has_key?(where) && @channels[where].quiet))
        sendmsg("PRIVMSG", where, line)
      end
    }
  end

  # perform a CTCP action with message +message+ to channel/nick +where+
  def action(where, message)
    sendq("PRIVMSG #{where} :\001ACTION #{message}\001")
    if(where =~ /^#/)
      log "* #{@nick} #{message}", where
    elsif (where =~ /^(\S*)!.*$/)
         log "* #{@nick}[#{where}] #{message}", $1
    else
         log "* #{@nick}[#{where}] #{message}", where
    end
  end

  # quick way to say "okay" (or equivalent) to +where+
  def okay(where)
    say where, @lang.get("okay")
  end

  # log message +message+ to a file determined by +where+. +where+ can be a
  # channel name, or a nick for private message logging
  def log(message, where="server")
    message = message.chomp
    stamp = Time.now.strftime("%Y/%m/%d %H:%M:%S")
    where = where.gsub(/[:!?$*()\/\\<>|"']/, "_")
    unless(@logs.has_key?(where))
      @logs[where] = File.new("#{@botclass}/logs/#{where}", "a")
      @logs[where].sync = true
    end
    @logs[where].puts "[#{stamp}] #{message}"
    #debug "[#{stamp}] <#{where}> #{message}"
  end
  
  # set topic of channel +where+ to +topic+
  def topic(where, topic)
    sendq "TOPIC #{where} :#{topic}"
  end

  # disconnect from the server and cleanup all plugins and modules
  def shutdown(message = nil)
    begin
      trap("SIGINT", "DEFAULT")
      trap("SIGTERM", "DEFAULT")
      trap("SIGHUP", "DEFAULT")
    rescue
      debug "failed to trap signals, probably running on windows?"
    end
    message = @lang.get("quit") if (message.nil? || message.empty?)
    debug "Clearing socket"
    @socket.clearq
    debug "Saving"
    save
    debug "Cleaning up"
    @plugins.cleanup
    debug "Logging quits"
    @channels.each_value {|v|
      log "@ quit (#{message})", v.name
    }
    # debug "Closing registries"
    # @registry.close
    debug "Cleaning up the db environment"
    DBTree.cleanup_env
    debug "Sending quit message"
    @socket.puts "QUIT :#{message}"
    debug "Flushing socket"
    @socket.flush
    debug "Shutting down socket"
    @socket.shutdown
    puts "rbot quit (#{message})"
  end
  
  # message:: optional IRC quit message
  # quit IRC, shutdown the bot
  def quit(message=nil)
    begin
      shutdown(message)
    ensure
      exit 0
    end
  end

  # totally shutdown and respawn the bot
  def restart(message = false)
    msg = message ? message : "restarting, back in #{@config['server.reconnect_wait']}..."
    shutdown(msg)
    sleep @config['server.reconnect_wait']
    # now we re-exec
    exec($0, *@argv)
  end

  # call the save method for bot's config, keywords, auth and all plugins
  def save
    @config.save
    @keywords.save
    @auth.save
    @plugins.save
    DBTree.cleanup_logs
  end

  # call the rescan method for the bot's lang, keywords and all plugins
  def rescan
    @lang.rescan
    @plugins.rescan
    @keywords.rescan
  end
  
  # channel:: channel to join
  # key::     optional channel key if channel is +s
  # join a channel
  def join(channel, key=nil)
    if(key)
      sendq "JOIN #{channel} :#{key}"
    else
      sendq "JOIN #{channel}"
    end
  end

  # part a channel
  def part(channel, message="")
    sendq "PART #{channel} :#{message}"
  end

  # attempt to change bot's nick to +name+
  def nickchg(name)
      sendq "NICK #{name}"
  end

  # changing mode
  def mode(channel, mode, target)
      sendq "MODE #{channel} #{mode} #{target}"
  end
  
  # m::     message asking for help
  # topic:: optional topic help is requested for
  # respond to online help requests
  def help(topic=nil)
    topic = nil if topic == ""
    case topic
    when nil
      helpstr = "help topics: core, auth, keywords"
      helpstr += @plugins.helptopics
      helpstr += " (help <topic> for more info)"
    when /^core$/i
      helpstr = corehelp
    when /^core\s+(.+)$/i
      helpstr = corehelp $1
    when /^auth$/i
      helpstr = @auth.help
    when /^auth\s+(.+)$/i
      helpstr = @auth.help $1
    when /^keywords$/i
      helpstr = @keywords.help
    when /^keywords\s+(.+)$/i
      helpstr = @keywords.help $1
    else
      unless(helpstr = @plugins.help(topic))
        helpstr = "no help for topic #{topic}"
      end
    end
    return helpstr
  end

  # returns a string describing the current status of the bot (uptime etc)
  def status
    secs_up = Time.new - @startup_time
    uptime = Utils.secs_to_string secs_up
    # return "Uptime #{uptime}, #{@plugins.length} plugins active, #{@registry.length} items stored in registry, #{@socket.lines_sent} lines sent, #{@socket.lines_received} received."
    return "Uptime #{uptime}, #{@plugins.length} plugins active, #{@socket.lines_sent} lines sent, #{@socket.lines_received} received."
  end

  # we'll ping the server every 30 seconds or so, and expect a response
  # before the next one come around..
  def start_server_pings
    @last_ping = nil
    # stop existing timers if running
    unless @ping_timer.nil?
      @timer.remove @ping_timer
      @ping_timer = nil
    end
    unless @pong_timer.nil?
      @timer.remove @pong_timer
      @pong_timer = nil
    end
    return unless @config['server.ping_timeout'] > 0
    # we want to respond to a hung server within 30 secs or so
    @ping_timer = @timer.add(30) {
      @last_ping = Time.now
      @socket.puts "PING :rbot"
    }
    @pong_timer = @timer.add(10) {
      unless @last_ping.nil?
        diff = Time.now - @last_ping
        unless diff < @config['server.ping_timeout']
          debug "no PONG from server for #{diff} seconds, reconnecting"
          begin
            @socket.shutdown
            # TODO
            # raise an exception to get back to the mainloop
          rescue
            debug "couldn't shutdown connection (already shutdown?)"
          end
          @last_ping = nil
        end
      end
    }
  end

  private

  # handle help requests for "core" topics
  def corehelp(topic="")
    case topic
      when "quit"
        return "quit [<message>] => quit IRC with message <message>"
      when "restart"
        return "restart => completely stop and restart the bot (including reconnect)"
      when "join"
        return "join <channel> [<key>] => join channel <channel> with secret key <key> if specified. #{@nick} also responds to invites if you have the required access level"
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
	#       when "topic"
	#         return "topic <channel> <message> => set topic of <channel> to <message>"
      when "quiet"
        return "quiet [in here|<channel>] => with no arguments, stop speaking in all channels, if \"in here\", stop speaking in this channel, or stop speaking in <channel>"
      when "talk"
        return "talk [in here|<channel>] => with no arguments, resume speaking in all channels, if \"in here\", resume speaking in this channel, or resume speaking in <channel>"
      when "version"
        return "version => describes software version"
      when "botsnack"
        return "botsnack => reward #{@nick} for being good"
      when "hello"
        return "hello|hi|hey|yo [#{@nick}] => greet the bot"
      else
        return "Core help topics: quit, restart, config, join, part, hide, save, rescan, nick, say, action, topic, quiet, talk, version, botsnack, hello"
    end
  end

  # handle incoming IRC PRIVMSG +m+
  def onprivmsg(m)
    # log it first
    if(m.action?)
      if(m.private?)
        log "* [#{m.sourcenick}(#{m.sourceaddress})] #{m.message}", m.sourcenick
      else
        log "* #{m.sourcenick} #{m.message}", m.target
      end
    else
      if(m.public?)
        log "<#{m.sourcenick}> #{m.message}", m.target
      else
        log "[#{m.sourcenick}(#{m.sourceaddress})] #{m.message}", m.sourcenick
      end
    end

    # pass it off to plugins that want to hear everything
    @plugins.delegate "listen", m

    if(m.private? && m.message =~ /^\001PING\s+(.+)\001/)
      notice m.sourcenick, "\001PING #$1\001"
      log "@ #{m.sourcenick} pinged me"
      return
    end

    if(m.address?)
      delegate_privmsg(m)
      case m.message
        when (/^join\s+(\S+)\s+(\S+)$/i)
          join $1, $2 if(@auth.allow?("join", m.source, m.replyto))
        when (/^join\s+(\S+)$/i)
          join $1 if(@auth.allow?("join", m.source, m.replyto))
        when (/^part$/i)
          part m.target if(m.public? && @auth.allow?("join", m.source, m.replyto))
        when (/^part\s+(\S+)$/i)
          part $1 if(@auth.allow?("join", m.source, m.replyto))
        when (/^quit(?:\s+(.*))?$/i)
          quit $1 if(@auth.allow?("quit", m.source, m.replyto))
        when (/^restart(?:\s+(.*))?$/i)
          restart $1 if(@auth.allow?("quit", m.source, m.replyto))
        when (/^hide$/i)
          join 0 if(@auth.allow?("join", m.source, m.replyto))
        when (/^save$/i)
          if(@auth.allow?("config", m.source, m.replyto))
            save
            m.okay
          end
        when (/^nick\s+(\S+)$/i)
          nickchg($1) if(@auth.allow?("nick", m.source, m.replyto))
        when (/^say\s+(\S+)\s+(.*)$/i)
          say $1, $2 if(@auth.allow?("say", m.source, m.replyto))
        when (/^action\s+(\S+)\s+(.*)$/i)
          action $1, $2 if(@auth.allow?("say", m.source, m.replyto))
	  # when (/^topic\s+(\S+)\s+(.*)$/i)
          #   topic $1, $2 if(@auth.allow?("topic", m.source, m.replyto))
        when (/^mode\s+(\S+)\s+(\S+)\s+(.*)$/i)
          mode $1, $2, $3 if(@auth.allow?("mode", m.source, m.replyto))
        when (/^ping$/i)
          say m.replyto, "pong"
        when (/^rescan$/i)
          if(@auth.allow?("config", m.source, m.replyto))
            m.reply "Saving ..."
            save
            m.reply "Rescanning ..."
            rescan
            m.okay
          end
        when (/^quiet$/i)
          if(auth.allow?("talk", m.source, m.replyto))
            m.okay
            @channels.each_value {|c| c.quiet = true }
          end
        when (/^quiet in (\S+)$/i)
          where = $1
          if(auth.allow?("talk", m.source, m.replyto))
            m.okay
            where.gsub!(/^here$/, m.target) if m.public?
            @channels[where].quiet = true if(@channels.has_key?(where))
          end
        when (/^talk$/i)
          if(auth.allow?("talk", m.source, m.replyto))
            @channels.each_value {|c| c.quiet = false }
            m.okay
          end
        when (/^talk in (\S+)$/i)
          where = $1
          if(auth.allow?("talk", m.source, m.replyto))
            where.gsub!(/^here$/, m.target) if m.public?
            @channels[where].quiet = false if(@channels.has_key?(where))
            m.okay
          end
        when (/^status\??$/i)
          m.reply status if auth.allow?("status", m.source, m.replyto)
        when (/^registry stats$/i)
          if auth.allow?("config", m.source, m.replyto)
            m.reply @registry.stat.inspect
          end
        when (/^(help\s+)?config(\s+|$)/)
          @config.privmsg(m)
        when (/^(version)|(introduce yourself)$/i)
          say m.replyto, "I'm a v. #{$version} rubybot, (c) Tom Gilbert - http://linuxbrit.co.uk/rbot/"
        when (/^help(?:\s+(.*))?$/i)
          say m.replyto, help($1)
          #TODO move these to a "chatback" plugin
        when (/^(botsnack|ciggie)$/i)
          say m.replyto, @lang.get("thanks_X") % m.sourcenick if(m.public?)
          say m.replyto, @lang.get("thanks") if(m.private?)
        when (/^(hello|howdy|hola|salut|bonjour|sup|niihau|hey|hi(\W|$)|yo(\W|$)).*/i)
          say m.replyto, @lang.get("hello_X") % m.sourcenick if(m.public?)
          say m.replyto, @lang.get("hello") if(m.private?)
      end
    else
      # stuff to handle when not addressed
      case m.message
        when (/^\s*(hello|howdy|hola|salut|bonjour|sup|niihau|hey|hi|yo(\W|$))[\s,-.]+#{Regexp.escape(@nick)}$/i)
          say m.replyto, @lang.get("hello_X") % m.sourcenick
        when (/^#{Regexp.escape(@nick)}!*$/)
          say m.replyto, @lang.get("hello_X") % m.sourcenick
        else
          @keywords.privmsg(m)
      end
    end
  end

  # log a message. Internal use only.
  def log_sent(type, where, message)
    case type
      when "NOTICE"
        if(where =~ /^#/)
          log "-=#{@nick}=- #{message}", where
        elsif (where =~ /(\S*)!.*/)
             log "[-=#{where}=-] #{message}", $1
        else
             log "[-=#{where}=-] #{message}"
        end
      when "PRIVMSG"
        if(where =~ /^#/)
          log "<#{@nick}> #{message}", where
        elsif (where =~ /^(\S*)!.*$/)
          log "[msg(#{where})] #{message}", $1
        else
          log "[msg(#{where})] #{message}", where
        end
    end
  end

  def onjoin(m)
    @channels[m.channel] = IRCChannel.new(m.channel) unless(@channels.has_key?(m.channel))
    if(m.address?)
      debug "joined channel #{m.channel}"
      log "@ Joined channel #{m.channel}", m.channel
    else
      log "@ #{m.sourcenick} joined channel #{m.channel}", m.channel
      @channels[m.channel].users[m.sourcenick] = Hash.new
      @channels[m.channel].users[m.sourcenick]["mode"] = ""
    end

    @plugins.delegate("listen", m)
    @plugins.delegate("join", m)
  end

  def onpart(m)
    if(m.address?)
      debug "left channel #{m.channel}"
      log "@ Left channel #{m.channel} (#{m.message})", m.channel
      @channels.delete(m.channel)
    else
      log "@ #{m.sourcenick} left channel #{m.channel} (#{m.message})", m.channel
      @channels[m.channel].users.delete(m.sourcenick)
    end
    
    # delegate to plugins
    @plugins.delegate("listen", m)
    @plugins.delegate("part", m)
  end

  # respond to being kicked from a channel
  def onkick(m)
    if(m.address?)
      debug "kicked from channel #{m.channel}"
      @channels.delete(m.channel)
      log "@ You have been kicked from #{m.channel} by #{m.sourcenick} (#{m.message})", m.channel
    else
      @channels[m.channel].users.delete(m.sourcenick)
      log "@ #{m.target} has been kicked from #{m.channel} by #{m.sourcenick} (#{m.message})", m.channel
    end

    @plugins.delegate("listen", m)
    @plugins.delegate("kick", m)
  end

  def ontopic(m)
    @channels[m.channel] = IRCChannel.new(m.channel) unless(@channels.has_key?(m.channel))
    @channels[m.channel].topic = m.topic if !m.topic.nil?
    @channels[m.channel].topic.timestamp = m.timestamp if !m.timestamp.nil?
    @channels[m.channel].topic.by = m.source if !m.source.nil?

	  debug "topic of channel #{m.channel} is now #{@channels[m.channel].topic}"
  end

  # delegate a privmsg to auth, keyword or plugin handlers
  def delegate_privmsg(message)
    [@auth, @plugins, @keywords].each {|m|
      break if m.privmsg(message)
    }
  end
end

end
