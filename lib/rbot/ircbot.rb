require 'thread'

require 'etc'
require 'fileutils'
require 'logger'

$debug = false unless $debug
$daemonize = false unless $daemonize

$dateformat = "%Y/%m/%d %H:%M:%S"
$logger = Logger.new($stderr)
$logger.datetime_format = $dateformat
$logger.level = $cl_loglevel if $cl_loglevel
$logger.level = 0 if $debug

def rawlog(level, message=nil, who_pos=1)
  call_stack = caller
  if call_stack.length > who_pos
    who = call_stack[who_pos].sub(%r{(?:.+)/([^/]+):(\d+)(:in .*)?}) { "#{$1}:#{$2}#{$3}" }
  else
    who = "(unknown)"
  end
  # Output each line. To distinguish between separate messages and multi-line
  # messages originating at the same time, we blank #{who} after the first message
  # is output.
  message.to_s.each_line { |l|
    $logger.add(level, l.chomp, who)
    who.gsub!(/./," ")
  }
end

def log_session_start
  $logger << "\n\n=== #{botclass} session started on #{Time.now.strftime($dateformat)} ===\n\n"
end

def log_session_end
  $logger << "\n\n=== #{botclass} session ended on #{Time.now.strftime($dateformat)} ===\n\n"
end

def debug(message=nil, who_pos=1)
  rawlog(Logger::Severity::DEBUG, message, who_pos)
end

def log(message=nil, who_pos=1)
  rawlog(Logger::Severity::INFO, message, who_pos)
end

def warning(message=nil, who_pos=1)
  rawlog(Logger::Severity::WARN, message, who_pos)
end

def error(message=nil, who_pos=1)
  rawlog(Logger::Severity::ERROR, message, who_pos)
end

def fatal(message=nil, who_pos=1)
  rawlog(Logger::Severity::FATAL, message, who_pos)
end

debug "debug test"
log "log test"
warning "warning test"
error "error test"
fatal "fatal test"

# The following global is used for the improved signal handling.
$interrupted = 0

# these first
require 'rbot/rbotconfig'
require 'rbot/config'
require 'rbot/utils'

require 'rbot/irc'
require 'rbot/rfc2812'
require 'rbot/keywords'
require 'rbot/ircsocket'
# require 'rbot/auth'
require 'rbot/botuser'
require 'rbot/timer'
require 'rbot/plugins'
# require 'rbot/channel'
require 'rbot/message'
require 'rbot/language'
require 'rbot/dbhash'
require 'rbot/registry'
require 'rbot/httputil'

module Irc

# Main bot class, which manages the various components, receives messages,
# handles them or passes them to plugins, and contains core functionality.
class IrcBot
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

  # server the bot is connected to
  # TODO multiserver
  attr_reader :server

  # the client personality of the bot
  # TODO multiserver
  attr_reader :client

  # bot's irc socket
  # TODO multiserver
  attr_reader :socket

  # bot's object registry, plugins get an interface to this for persistant
  # storage (hash interface tied to a bdb file, plugins use Accessors to store
  # and restore objects in their own namespaces.)
  attr_reader :registry

  # bot's plugins. This is an instance of class Plugins
  attr_reader :plugins

  # bot's httputil help object, for fetching resources via http. Sets up
  # proxies etc as defined by the bot configuration/environment
  attr_reader :httputil

  # bot User in the client/server connection
  attr_reader :myself

  # bot User in the client/server connection
  def nick
    myself.nick
  end

  # create a new IrcBot with botclass +botclass+
  def initialize(botclass, params = {})
    # BotConfig for the core bot
    # TODO should we split socket stuff into ircsocket, etc?
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
    BotConfig.register BotConfigFloatValue.new('server.sendq_delay',
      :default => 2.0, :validate => Proc.new{|v| v >= 0},
      :desc => "(flood prevention) the delay between sending messages to the server (in seconds)",
      :on_change => Proc.new {|bot, v| bot.socket.sendq_delay = v })
    BotConfig.register BotConfigIntegerValue.new('server.sendq_burst',
      :default => 4, :validate => Proc.new{|v| v >= 0},
      :desc => "(flood prevention) max lines to burst to the server before throttling. Most ircd's allow bursts of up 5 lines",
      :on_change => Proc.new {|bot, v| bot.socket.sendq_burst = v })
    BotConfig.register BotConfigStringValue.new('server.byterate',
      :default => "400/2", :validate => Proc.new{|v| v.match(/\d+\/\d/)},
      :desc => "(flood prevention) max bytes/seconds rate to send the server. Most ircd's have limits of 512 bytes/2 seconds",
      :on_change => Proc.new {|bot, v| bot.socket.byterate = v })
    BotConfig.register BotConfigIntegerValue.new('server.ping_timeout',
      :default => 30, :validate => Proc.new{|v| v >= 0},
      :on_change => Proc.new {|bot, v| bot.start_server_pings},
      :desc => "reconnect if server doesn't respond to PING within this many seconds (set to 0 to disable)")

    BotConfig.register BotConfigStringValue.new('irc.nick', :default => "rbot",
      :desc => "IRC nickname the bot should attempt to use", :wizard => true,
      :on_change => Proc.new{|bot, v| bot.sendq "NICK #{v}" })
    BotConfig.register BotConfigStringValue.new('irc.user', :default => "rbot",
      :requires_restart => true,
      :desc => "local user the bot should appear to be", :wizard => true)
    BotConfig.register BotConfigArrayValue.new('irc.join_channels',
      :default => [], :wizard => true,
      :desc => "What channels the bot should always join at startup. List multiple channels using commas to separate. If a channel requires a password, use a space after the channel name. e.g: '#chan1, #chan2, #secretchan secritpass, #chan3'")
    BotConfig.register BotConfigArrayValue.new('irc.ignore_users',
      :default => [], 
      :desc => "Which users to ignore input from. This is mainly to avoid bot-wars triggered by creative people")

    BotConfig.register BotConfigIntegerValue.new('core.save_every',
      :default => 60, :validate => Proc.new{|v| v >= 0},
      # TODO change timer via on_change proc
      :desc => "How often the bot should persist all configuration to disk (in case of a server crash, for example)")

    BotConfig.register BotConfigBooleanValue.new('core.run_as_daemon',
      :default => false, :requires_restart => true,
      :desc => "Should the bot run as a daemon?")

    BotConfig.register BotConfigStringValue.new('log.file',
      :default => false, :requires_restart => true,
      :desc => "Name of the logfile to which console messages will be redirected when the bot is run as a daemon")
    BotConfig.register BotConfigIntegerValue.new('log.level',
      :default => 1, :requires_restart => false,
      :validate => Proc.new { |v| (0..5).include?(v) },
      :on_change => Proc.new { |bot, v|
        $logger.level = v
      },
      :desc => "The minimum logging level (0=DEBUG,1=INFO,2=WARN,3=ERROR,4=FATAL) for console messages")
    BotConfig.register BotConfigIntegerValue.new('log.keep',
      :default => 1, :requires_restart => true,
      :validate => Proc.new { |v| v >= 0 },
      :desc => "How many old console messages logfiles to keep")
    BotConfig.register BotConfigIntegerValue.new('log.max_size',
      :default => 10, :requires_restart => true,
      :validate => Proc.new { |v| v > 0 },
      :desc => "Maximum console messages logfile size (in megabytes)")

    @argv = params[:argv]

    unless FileTest.directory? Config::coredir
      error "core directory '#{Config::coredir}' not found, did you setup.rb?"
      exit 2
    end

    unless FileTest.directory? Config::datadir
      error "data directory '#{Config::datadir}' not found, did you setup.rb?"
      exit 2
    end

    unless botclass and not botclass.empty?
      # We want to find a sensible default.
      #  * On POSIX systems we prefer ~/.rbot for the effective uid of the process
      #  * On Windows (at least the NT versions) we want to put our stuff in the
      #    Application Data folder.
      # We don't use any particular O/S detection magic, exploiting the fact that
      # Etc.getpwuid is nil on Windows
      if Etc.getpwuid(Process::Sys.geteuid)
        botclass = Etc.getpwuid(Process::Sys.geteuid)[:dir].dup
      else
        if ENV.has_key?('APPDATA')
          botclass = ENV['APPDATA'].dup
          botclass.gsub!("\\","/")
        end
      end
      botclass += "/.rbot"
    end
    botclass = File.expand_path(botclass)
    @botclass = botclass.gsub(/\/$/, "")

    unless FileTest.directory? botclass
      log "no #{botclass} directory found, creating from templates.."
      if FileTest.exist? botclass
        error "file #{botclass} exists but isn't a directory"
        exit 2
      end
      FileUtils.cp_r Config::datadir+'/templates', botclass
    end

    Dir.mkdir("#{botclass}/logs") unless File.exist?("#{botclass}/logs")
    Dir.mkdir("#{botclass}/registry") unless File.exist?("#{botclass}/registry")

    @ping_timer = nil
    @pong_timer = nil
    @last_ping = nil
    @startup_time = Time.new

    begin
      @config = BotConfig.configmanager
      @config.bot_associate(self)
    rescue => e
      fatal e.inspect
      fatal e.backtrace.join("\n")
      log_session_end
      exit 2
    end

    if @config['core.run_as_daemon']
      $daemonize = true
    end

    @logfile = @config['log.file']
    if @logfile.class!=String || @logfile.empty?
      @logfile = "#{botclass}/#{File.basename(botclass).gsub(/^\.+/,'')}.log"
    end

    # See http://blog.humlab.umu.se/samuel/archives/000107.html
    # for the backgrounding code 
    if $daemonize
      begin
        exit if fork
        Process.setsid
        exit if fork
      rescue NotImplementedError
        warning "Could not background, fork not supported"
      rescue => e
        warning "Could not background. #{e.inspect}"
      end
      Dir.chdir botclass
      # File.umask 0000                # Ensure sensible umask. Adjust as needed.
      log "Redirecting standard input/output/error"
      begin
        STDIN.reopen "/dev/null"
      rescue Errno::ENOENT
        # On Windows, there's not such thing as /dev/null
        STDIN.reopen "NUL"
      end
      def STDOUT.write(str=nil)
        log str, 2
        return str.to_s.length
      end
      def STDERR.write(str=nil)
        if str.to_s.match(/:\d+: warning:/)
          warning str, 2
        else
          error str, 2
        end
        return str.to_s.length
      end
    end

    # Set the new logfile and loglevel. This must be done after the daemonizing
    $logger = Logger.new(@logfile, @config['log.keep'], @config['log.max_size']*1024*1024)
    $logger.datetime_format= $dateformat
    $logger.level = @config['log.level']
    $logger.level = $cl_loglevel if $cl_loglevel
    $logger.level = 0 if $debug

    log_session_start

    @registry = BotRegistry.new self

    @timer = Timer::Timer.new(1.0) # only need per-second granularity
    @timer.add(@config['core.save_every']) { save } if @config['core.save_every']

    @logs = Hash.new

    @httputil = Utils::HttpUtil.new(self)

    @lang = Language::Language.new(@config['core.language'])

    # @keywords = Keywords.new(self)

    begin
      @auth = Auth::authmanager
      @auth.bot_associate(self)
      # @auth.load("#{botclass}/botusers.yaml")
    rescue => e
      fatal e.inspect
      fatal e.backtrace.join("\n")
      log_session_end
      exit 2
    end
    @auth.everyone.set_default_permission("*", true)

    Dir.mkdir("#{botclass}/plugins") unless File.exist?("#{botclass}/plugins")
    @plugins = Plugins::pluginmanager
    @plugins.bot_associate(self)
    @plugins.add_botmodule_dir(Config::coredir)
    @plugins.add_botmodule_dir("#{botclass}/plugins")
    @plugins.add_botmodule_dir(Config::datadir + "/plugins")
    @plugins.scan

    @socket = IrcSocket.new(@config['server.name'], @config['server.port'], @config['server.bindhost'], @config['server.sendq_delay'], @config['server.sendq_burst'])
    @client = IrcClient.new
    @server = @client.server
    @myself = @client.client
    @myself.nick = @config['irc.nick']

    # Channels where we are quiet
    # It's nil when we are not quiet, an empty list when we are quiet
    # in all channels, a list of channels otherwise
    @quiet = nil

    @client[:welcome] = proc {|data|
      irclog "joined server #{@client.server} as #{myself}", "server"

      @plugins.delegate("connect")

      @config['irc.join_channels'].each { |c|
        debug "autojoining channel #{c}"
        if(c =~ /^(\S+)\s+(\S+)$/i)
          join $1, $2
        else
          join c if(c)
        end
      }
    }
    @client[:isupport] = proc { |data|
      # TODO this needs to go into rfc2812.rb
      # Since capabs are two-steps processes, server.supports[:capab]
      # should be a three-state: nil, [], [....]
      sendq "CAPAB IDENTIFY-MSG" if @server.supports[:capab]
    }
    @client[:datastr] = proc { |data|
      # TODO this needs to go into rfc2812.rb
      if data[:text] == "IDENTIFY-MSG"
        @server.capabilities["identify-msg".to_sym] = true
      else
        debug "Not handling RPL_DATASTR #{data[:servermessage]}"
      end
    }
    @client[:privmsg] = proc { |data|
      m = PrivMessage.new(self, @server, data[:source], data[:target], data[:message])

      # TODO use the new Netmask class
      # @config['irc.ignore_users'].each { |mask| return if Irc.netmaskmatch(mask,m.source) }

      irclogprivmsg(m)

      @plugins.delegate "listen", m
      @plugins.privmsg(m) if m.address?
    }
    @client[:notice] = proc { |data|
      message = NoticeMessage.new(self, @server, data[:source], data[:target], data[:message])
      # pass it off to plugins that want to hear everything
      @plugins.delegate "listen", message
    }
    @client[:motd] = proc { |data|
      data[:motd].each_line { |line|
        irclog "MOTD: #{line}", "server"
      }
    }
    @client[:nicktaken] = proc { |data|
      nickchg "#{data[:nick]}_"
      @plugins.delegate "nicktaken", data[:nick]
    }
    @client[:badnick] = proc {|data|
      warning "bad nick (#{data[:nick]})"
    }
    @client[:ping] = proc {|data|
      sendq "PONG #{data[:pingid]}"
    }
    @client[:pong] = proc {|data|
      @last_ping = nil
    }
    @client[:nick] = proc {|data|
      source = data[:source]
      old = data[:oldnick]
      new = data[:newnick]
      m = NickMessage.new(self, @server, source, old, new)
      if source == myself
        debug "my nick is now #{new}"
      end
      data[:is_on].each { |ch|
          irclog "@ #{old} is now known as #{new}", ch
      }
      @plugins.delegate("listen", m)
      @plugins.delegate("nick", m)
    }
    @client[:quit] = proc {|data|
      source = data[:source]
      message = data[:message]
      m = QuitMessage.new(self, @server, source, source, message)
      data[:was_on].each { |ch|
        irclog "@ Quit: #{source}: #{message}", ch
      }
      @plugins.delegate("listen", m)
      @plugins.delegate("quit", m)
    }
    @client[:mode] = proc {|data|
      irclog "@ Mode #{data[:modestring]} by #{data[:source]}", data[:channel]
    }
    @client[:join] = proc {|data|
      m = JoinMessage.new(self, @server, data[:source], data[:channel], data[:message])
      irclogjoin(m)

      @plugins.delegate("listen", m)
      @plugins.delegate("join", m)
    }
    @client[:part] = proc {|data|
      m = PartMessage.new(self, @server, data[:source], data[:channel], data[:message])
      irclogpart(m)

      @plugins.delegate("listen", m)
      @plugins.delegate("part", m)
    }
    @client[:kick] = proc {|data|
      m = KickMessage.new(self, @server, data[:source], data[:target], data[:channel],data[:message])
      irclogkick(m)

      @plugins.delegate("listen", m)
      @plugins.delegate("kick", m)
    }
    @client[:invite] = proc {|data|
      if data[:target] == myself
        join data[:channel] if @auth.allow?("join", data[:source], data[:source].nick)
      end
    }
    @client[:changetopic] = proc {|data|
      m = TopicMessage.new(self, @server, data[:source], data[:channel], data[:topic])
      irclogtopic(m)

      @plugins.delegate("listen", m)
      @plugins.delegate("topic", m)
    }
    @client[:topic] = proc { |data|
      irclog "@ Topic is \"#{data[:topic]}\"", data[:channel]
    }
    @client[:topicinfo] = proc { |data|
      channel = data[:channel]
      topic = channel.topic
      irclog "@ Topic set by #{topic.set_by} on #{topic.set_on}", channel
      m = TopicMessage.new(self, @server, data[:source], channel, topic)

      @plugins.delegate("listen", m)
      @plugins.delegate("topic", m)
    }
    @client[:names] = proc { |data|
      @plugins.delegate "names", data[:channel], data[:users]
    }
    @client[:unknown] = proc { |data|
      #debug "UNKNOWN: #{data[:serverstring]}"
      irclog data[:serverstring], ".unknown"
    }
  end

  # checks if we should be quiet on a channel
  def quiet_on?(channel)
    return false unless @quiet
    return true if @quiet.empty?
    return @quiet.include?(channel.to_s)
  end

  def set_quiet(channel=nil)
    if channel
      @quiet << channel.to_s unless @quiet.include?(channel.to_s)
    else
      @quiet = []
    end
  end

  def reset_quiet(channel=nil)
    if channel
      @quiet.delete_if { |x| x == channel.to_s }
    else
      @quiet = nil
    end
  end

  # things to do when we receive a signal
  def got_sig(sig)
    debug "received #{sig}, queueing quit"
    $interrupted += 1
    debug "interrupted #{$interrupted} times"
    if $interrupted >= 5
      debug "drastic!"
      log_session_end
      exit 2
    elsif $interrupted >= 3
      debug "quitting"
      quit
    end
  end

  # connect the bot to IRC
  def connect
    begin
      trap("SIGINT") { got_sig("SIGINT") }
      trap("SIGTERM") { got_sig("SIGTERM") }
      trap("SIGHUP") { got_sig("SIGHUP") }
    rescue ArgumentError => e
      debug "failed to trap signals (#{e.inspect}): running on Windows?"
    rescue => e
      debug "failed to trap signals: #{e.inspect}"
    end
    begin
      quit if $interrupted > 0
      @socket.connect
    rescue => e
      raise e.class, "failed to connect to IRC server at #{@config['server.name']} #{@config['server.port']}: " + e
    end
    @socket.emergency_puts "PASS " + @config['server.password'] if @config['server.password']
    @socket.emergency_puts "NICK #{@config['irc.nick']}\nUSER #{@config['irc.user']} 4 #{@config['server.name']} :Ruby bot. (c) Tom Gilbert"
    start_server_pings
  end

  # begin event handling loop
  def mainloop
    while true
      begin
	quit if $interrupted > 0
        connect
        @timer.start

        while @socket.connected?
          if @socket.select
            break unless reply = @socket.gets
            @client.process reply
          end
	  quit if $interrupted > 0
        end

      # I despair of this. Some of my users get "connection reset by peer"
      # exceptions that ARENT SocketError's. How am I supposed to handle
      # that?
      rescue SystemExit
        log_session_end
        exit 0
      rescue Errno::ETIMEDOUT, TimeoutError, SocketError => e
        error "network exception: #{e.class}: #{e}"
        debug e.backtrace.join("\n")
      rescue BDB::Fatal => e
        fatal "fatal bdb error: #{e.class}: #{e}"
        fatal e.backtrace.join("\n")
        DBTree.stats
        # Why restart? DB problems are serious stuff ...
        # restart("Oops, we seem to have registry problems ...")
        log_session_end
        exit 2
      rescue Exception => e
        error "non-net exception: #{e.class}: #{e}"
        error e.backtrace.join("\n")
      rescue => e
        fatal "unexpected exception: #{e.class}: #{e}"
        fatal e.backtrace.join("\n")
        log_session_end
        exit 2
      end

      stop_server_pings
      @server.clear
      if @socket.connected?
        @socket.clearq
        @socket.shutdown
      end

      log "disconnected"

      quit if $interrupted > 0

      log "waiting to reconnect"
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
  def sendmsg(type, where, message, chan=nil, ring=0)
    # limit it according to the byterate, splitting the message
    # taking into consideration the actual message length
    # and all the extra stuff
    # TODO allow something to do for commands that produce too many messages
    # TODO example: math 10**10000
    left = @socket.bytes_per - type.length - where.to_s.length - 4
    begin
      if(left >= message.length)
        sendq "#{type} #{where} :#{message}", chan, ring
        log_sent(type, where, message)
        return
      end
      line = message.slice!(0, left)
      lastspace = line.rindex(/\s+/)
      if(lastspace)
        message = line.slice!(lastspace, line.length) + message
        message.gsub!(/^\s+/, "")
      end
      sendq "#{type} #{where} :#{line}", chan, ring
      log_sent(type, where, line)
    end while(message.length > 0)
  end

  # queue an arbitraty message for the server
  def sendq(message="", chan=nil, ring=0)
    # temporary
    @socket.queue(message, chan, ring)
  end

  # send a notice message to channel/nick +where+
  def notice(where, message, mchan="", mring=-1)
    if mchan == ""
      chan = where
    else
      chan = mchan
    end
    if mring < 0
      case where
      when User
        ring = 1
      else
        ring = 2
      end
    else
      ring = mring
    end
    message.each_line { |line|
      line.chomp!
      next unless(line.length > 0)
      sendmsg "NOTICE", where, line, chan, ring
    }
  end

  # say something (PRIVMSG) to channel/nick +where+
  def say(where, message, mchan="", mring=-1)
    if mchan == ""
      chan = where
    else
      chan = mchan
    end
    if mring < 0
      case where
      when User
        ring = 1
      else
        ring = 2
      end
    else
      ring = mring
    end
    message.to_s.gsub(/[\r\n]+/, "\n").each_line { |line|
      line.chomp!
      next unless(line.length > 0)
      unless quiet_on?(where)
        sendmsg "PRIVMSG", where, line, chan, ring 
      end
    }
  end

  # perform a CTCP action with message +message+ to channel/nick +where+
  def action(where, message, mchan="", mring=-1)
    if mchan == ""
      chan = where
    else
      chan = mchan
    end
    if mring < 0
      case where
      when Channel
        ring = 2
      else
        ring = 1
      end
    else
      ring = mring
    end
    sendq "PRIVMSG #{where} :\001ACTION #{message}\001", chan, ring
    case where
    when Channel
      irclog "* #{myself} #{message}", where
    else
      irclog "* #{myself}[#{where}] #{message}", where
    end
  end

  # quick way to say "okay" (or equivalent) to +where+
  def okay(where)
    say where, @lang.get("okay")
  end

  # log IRC-related message +message+ to a file determined by +where+.
  # +where+ can be a channel name, or a nick for private message logging
  def irclog(message, where="server")
    message = message.chomp
    stamp = Time.now.strftime("%Y/%m/%d %H:%M:%S")
    where = where.to_s.gsub(/[:!?$*()\/\\<>|"']/, "_")
    unless(@logs.has_key?(where))
      @logs[where] = File.new("#{@botclass}/logs/#{where}", "a")
      @logs[where].sync = true
    end
    @logs[where].puts "[#{stamp}] #{message}"
    #debug "[#{stamp}] <#{where}> #{message}"
  end

  # set topic of channel +where+ to +topic+
  def topic(where, topic)
    sendq "TOPIC #{where} :#{topic}", where, 2
  end

  # disconnect from the server and cleanup all plugins and modules
  def shutdown(message = nil)
    debug "Shutting down ..."
    ## No we don't restore them ... let everything run through
    # begin
    #   trap("SIGINT", "DEFAULT")
    #   trap("SIGTERM", "DEFAULT")
    #   trap("SIGHUP", "DEFAULT")
    # rescue => e
    #   debug "failed to restore signals: #{e.inspect}\nProbably running on windows?"
    # end
    message = @lang.get("quit") if (message.nil? || message.empty?)
    if @socket.connected?
      debug "Clearing socket"
      @socket.clearq
      debug "Sending quit message"
      @socket.emergency_puts "QUIT :#{message}"
      debug "Flushing socket"
      @socket.flush
      debug "Shutting down socket"
      @socket.shutdown
    end
    debug "Logging quits"
    @server.channels.each { |ch|
      irclog "@ quit (#{message})", ch
    }
    debug "Saving"
    save
    debug "Cleaning up"
    @plugins.cleanup
    # debug "Closing registries"
    # @registry.close
    debug "Cleaning up the db environment"
    DBTree.cleanup_env
    log "rbot quit (#{message})"
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
    # Note, this fails on Windows
    exec($0, *@argv)
  end

  # call the save method for bot's config, keywords, auth and all plugins
  def save
    @config.save
    # @keywords.save
    @auth.save
    @plugins.save
    DBTree.cleanup_logs
  end

  # call the rescan method for the bot's lang, keywords and all plugins
  def rescan
    @lang.rescan
    @plugins.rescan
    # @keywords.rescan
  end

  # channel:: channel to join
  # key::     optional channel key if channel is +s
  # join a channel
  def join(channel, key=nil)
    if(key)
      sendq "JOIN #{channel} :#{key}", channel, 2
    else
      sendq "JOIN #{channel}", channel, 2
    end
  end

  # part a channel
  def part(channel, message="")
    sendq "PART #{channel} :#{message}", channel, 2
  end

  # attempt to change bot's nick to +name+
  def nickchg(name)
      sendq "NICK #{name}"
  end

  # changing mode
  def mode(channel, mode, target)
      sendq "MODE #{channel} #{mode} #{target}", channel, 2
  end

  # m::     message asking for help
  # topic:: optional topic help is requested for
  # respond to online help requests
  def help(topic=nil)
    topic = nil if topic == ""
    case topic
    when nil
      helpstr = "help topics: "
      helpstr += @plugins.helptopics
      helpstr += " (help <topic> for more info)"
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
    stop_server_pings
    return unless @config['server.ping_timeout'] > 0
    # we want to respond to a hung server within 30 secs or so
    @ping_timer = @timer.add(30) {
      @last_ping = Time.now
      @socket.queue "PING :rbot"
    }
    @pong_timer = @timer.add(10) {
      unless @last_ping.nil?
        diff = Time.now - @last_ping
        unless diff < @config['server.ping_timeout']
          debug "no PONG from server for #{diff} seconds, reconnecting"
          begin
            @socket.shutdown
          rescue
            debug "couldn't shutdown connection (already shutdown?)"
          end
          @last_ping = nil
          raise TimeoutError, "no PONG from server in #{diff} seconds"
        end
      end
    }
  end

  def stop_server_pings
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
  end

  private

  def irclogprivmsg(m)
    if(m.action?)
      if(m.private?)
        irclog "* [#{m.sourcenick}(#{m.sourceaddress})] #{m.message}", m.sourcenick
      else
        irclog "* #{m.sourcenick} #{m.message}", m.target
      end
    else
      if(m.public?)
        irclog "<#{m.sourcenick}> #{m.message}", m.target
      else
        irclog "[#{m.sourcenick}(#{m.sourceaddress})] #{m.message}", m.sourcenick
      end
    end
  end

  # log a message. Internal use only.
  def log_sent(type, where, message)
    case type
      when "NOTICE"
        case where
        when Channel
          irclog "-=#{myself}=- #{message}", where
        when User
             irclog "[-=#{where}=-] #{message}", $1
        else
             irclog "[-=#{where}=-] #{message}", where
        end
      when "PRIVMSG"
        case where
        when Channel
          irclog "<#{myself}> #{message}", where
        when User
          irclog "[msg(#{where})] #{message}", $1
        else
          irclog "[msg(#{where})] #{message}", where
        end
    end
  end

  def irclogjoin(m)
    if m.address?
      debug "joined channel #{m.channel}"
      irclog "@ Joined channel #{m.channel}", m.channel
    else
      irclog "@ #{m.sourcenick} joined channel #{m.channel}", m.channel
    end
  end

  def irclogpart(m)
    if(m.address?)
      debug "left channel #{m.channel}"
      irclog "@ Left channel #{m.channel} (#{m.message})", m.channel
    else
      irclog "@ #{m.sourcenick} left channel #{m.channel} (#{m.message})", m.channel
    end
  end

  def irclogkick(m)
    if(m.address?)
      debug "kicked from channel #{m.channel}"
      irclog "@ You have been kicked from #{m.channel} by #{m.sourcenick} (#{m.message})", m.channel
    else
      irclog "@ #{m.target} has been kicked from #{m.channel} by #{m.sourcenick} (#{m.message})", m.channel
    end
  end

  def irclogtopic(m)
    if m.source == myself
      irclog "@ I set topic \"#{m.topic}\"", m.channel
    else
      irclog "@ #{m.source} set topic \"#{m.topic}\"", m.channel
    end
  end

end

end
