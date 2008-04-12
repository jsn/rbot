#-- vim:sw=2:et
#++
#
# :title: rbot core

require 'thread'

require 'etc'
require 'fileutils'
require 'logger'

$debug = false unless $debug
$daemonize = false unless $daemonize

$dateformat = "%Y/%m/%d %H:%M:%S"
$logger = Logger.new($stderr)
$logger.datetime_format = $dateformat
$logger.level = $cl_loglevel if defined? $cl_loglevel
$logger.level = 0 if $debug

require 'pp'

unless Kernel.instance_methods.include?("pretty_inspect")
  def pretty_inspect
    PP.pp(self, '')
  end
  public :pretty_inspect
end

class Exception
  def pretty_print(q)
    q.group(1, "#<%s: %s" % [self.class, self.message], ">") {
      if self.backtrace and not self.backtrace.empty?
        q.text "\n"
        q.seplist(self.backtrace, lambda { q.text "\n" } ) { |l| q.text l }
      end
    }
  end
end

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
  # Also, we output strings as-is but for other objects we use pretty_inspect
  case message
  when String
    str = message
  else
    str = message.pretty_inspect
  end
  str.each_line { |l|
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
require 'rbot/load-gettext'
require 'rbot/config'
require 'rbot/config-compat'

require 'rbot/irc'
require 'rbot/rfc2812'
require 'rbot/ircsocket'
require 'rbot/botuser'
require 'rbot/timer'
require 'rbot/plugins'
require 'rbot/message'
require 'rbot/language'
require 'rbot/dbhash'
require 'rbot/registry'

module Irc

# Main bot class, which manages the various components, receives messages,
# handles them or passes them to plugins, and contains core functionality.
class Bot
  COPYRIGHT_NOTICE = "(c) Tom Gilbert and the rbot development team"
  SOURCE_URL = "http://ruby-rbot.org"
  # the bot's Auth data
  attr_reader :auth

  # the bot's Config data
  attr_reader :config

  # the botclass for this bot (determines configdir among other things)
  attr_reader :botclass

  # used to perform actions periodically (saves configuration once per minute
  # by default)
  attr_reader :timer

  # synchronize with this mutex while touching permanent data files:
  # saving, flushing, cleaning up ...
  attr_reader :save_mutex

  # bot's Language data
  attr_reader :lang

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
  attr_accessor :httputil

  # server we are connected to
  # TODO multiserver
  def server
    @client.server
  end

  # bot User in the client/server connection
  # TODO multiserver
  def myself
    @client.user
  end

  # bot User in the client/server connection
  def nick
    myself.nick
  end

  # bot inspection
  # TODO multiserver
  def inspect
    ret = self.to_s[0..-2]
    ret << ' version=' << $version.inspect
    ret << ' botclass=' << botclass.inspect
    ret << ' lang="' << lang.language
    if defined?(GetText)
      ret << '/' << locale
    end
    ret << '"'
    ret << ' nick=' << nick.inspect
    ret << ' server='
    if server
      ret << (server.to_s + (socket ?
        ' [' << socket.server_uri.to_s << ']' : '')).inspect
      unless server.channels.empty?
        ret << " channels="
        ret << server.channels.map { |c|
          "%s%s" % [c.modes_of(nick).map { |m|
            server.prefix_for_mode(m)
          }, c.name]
        }.inspect
      end
    else
      ret << '(none)'
    end
    ret << ' plugins=' << plugins.inspect
    ret << ">"
  end


  # create a new Bot with botclass +botclass+
  def initialize(botclass, params = {})
    # Config for the core bot
    # TODO should we split socket stuff into ircsocket, etc?
    Config.register Config::ArrayValue.new('server.list',
      :default => ['irc://localhost'], :wizard => true,
      :requires_restart => true,
      :desc => "List of irc servers rbot should try to connect to. Use comma to separate values. Servers are in format 'server.doma.in:port'. If port is not specified, default value (6667) is used.")
    Config.register Config::BooleanValue.new('server.ssl',
      :default => false, :requires_restart => true, :wizard => true,
      :desc => "Use SSL to connect to this server?")
    Config.register Config::StringValue.new('server.password',
      :default => false, :requires_restart => true,
      :desc => "Password for connecting to this server (if required)",
      :wizard => true)
    Config.register Config::StringValue.new('server.bindhost',
      :default => false, :requires_restart => true,
      :desc => "Specific local host or IP for the bot to bind to (if required)",
      :wizard => true)
    Config.register Config::IntegerValue.new('server.reconnect_wait',
      :default => 5, :validate => Proc.new{|v| v >= 0},
      :desc => "Seconds to wait before attempting to reconnect, on disconnect")
    Config.register Config::FloatValue.new('server.sendq_delay',
      :default => 2.0, :validate => Proc.new{|v| v >= 0},
      :desc => "(flood prevention) the delay between sending messages to the server (in seconds)",
      :on_change => Proc.new {|bot, v| bot.socket.sendq_delay = v })
    Config.register Config::IntegerValue.new('server.sendq_burst',
      :default => 4, :validate => Proc.new{|v| v >= 0},
      :desc => "(flood prevention) max lines to burst to the server before throttling. Most ircd's allow bursts of up 5 lines",
      :on_change => Proc.new {|bot, v| bot.socket.sendq_burst = v })
    Config.register Config::IntegerValue.new('server.ping_timeout',
      :default => 30, :validate => Proc.new{|v| v >= 0},
      :desc => "reconnect if server doesn't respond to PING within this many seconds (set to 0 to disable)")

    Config.register Config::StringValue.new('irc.nick', :default => "rbot",
      :desc => "IRC nickname the bot should attempt to use", :wizard => true,
      :on_change => Proc.new{|bot, v| bot.sendq "NICK #{v}" })
    Config.register Config::StringValue.new('irc.name',
      :default => "Ruby bot", :requires_restart => true,
      :desc => "IRC realname the bot should use")
    Config.register Config::BooleanValue.new('irc.name_copyright',
      :default => true, :requires_restart => true,
      :desc => "Append copyright notice to bot realname? (please don't disable unless it's really necessary)")
    Config.register Config::StringValue.new('irc.user', :default => "rbot",
      :requires_restart => true,
      :desc => "local user the bot should appear to be", :wizard => true)
    Config.register Config::ArrayValue.new('irc.join_channels',
      :default => [], :wizard => true,
      :desc => "What channels the bot should always join at startup. List multiple channels using commas to separate. If a channel requires a password, use a space after the channel name. e.g: '#chan1, #chan2, #secretchan secritpass, #chan3'")
    Config.register Config::ArrayValue.new('irc.ignore_users',
      :default => [],
      :desc => "Which users to ignore input from. This is mainly to avoid bot-wars triggered by creative people")

    Config.register Config::IntegerValue.new('core.save_every',
      :default => 60, :validate => Proc.new{|v| v >= 0},
      :on_change => Proc.new { |bot, v|
        if @save_timer
          if v > 0
            @timer.reschedule(@save_timer, v)
            @timer.unblock(@save_timer)
          else
            @timer.block(@save_timer)
          end
        else
          if v > 0
            @save_timer = @timer.add(v) { bot.save }
          end
          # Nothing to do when v == 0
        end
      },
      :desc => "How often the bot should persist all configuration to disk (in case of a server crash, for example)")

    Config.register Config::BooleanValue.new('core.run_as_daemon',
      :default => false, :requires_restart => true,
      :desc => "Should the bot run as a daemon?")

    Config.register Config::StringValue.new('log.file',
      :default => false, :requires_restart => true,
      :desc => "Name of the logfile to which console messages will be redirected when the bot is run as a daemon")
    Config.register Config::IntegerValue.new('log.level',
      :default => 1, :requires_restart => false,
      :validate => Proc.new { |v| (0..5).include?(v) },
      :on_change => Proc.new { |bot, v|
        $logger.level = v
      },
      :desc => "The minimum logging level (0=DEBUG,1=INFO,2=WARN,3=ERROR,4=FATAL) for console messages")
    Config.register Config::IntegerValue.new('log.keep',
      :default => 1, :requires_restart => true,
      :validate => Proc.new { |v| v >= 0 },
      :desc => "How many old console messages logfiles to keep")
    Config.register Config::IntegerValue.new('log.max_size',
      :default => 10, :requires_restart => true,
      :validate => Proc.new { |v| v > 0 },
      :desc => "Maximum console messages logfile size (in megabytes)")

    Config.register Config::ArrayValue.new('plugins.path',
      :wizard => true, :default => ['(default)', '(default)/games', '(default)/contrib'],
      :requires_restart => false,
      :on_change => Proc.new { |bot, v| bot.setup_plugins_path },
      :desc => "Where the bot should look for plugins. List multiple directories using commas to separate. Use '(default)' for default prepackaged plugins collection, '(default)/contrib' for prepackaged unsupported plugins collection")

    Config.register Config::EnumValue.new('send.newlines',
      :values => ['split', 'join'], :default => 'split',
      :on_change => Proc.new { |bot, v|
        bot.set_default_send_options :newlines => v.to_sym
      },
      :desc => "When set to split, messages with embedded newlines will be sent as separate lines. When set to join, newlines will be replaced by the value of join_with")
    Config.register Config::StringValue.new('send.join_with',
      :default => ' ',
      :on_change => Proc.new { |bot, v|
        bot.set_default_send_options :join_with => v.dup
      },
      :desc => "String used to replace newlines when send.newlines is set to join")
    Config.register Config::IntegerValue.new('send.max_lines',
      :default => 5,
      :validate => Proc.new { |v| v >= 0 },
      :on_change => Proc.new { |bot, v|
        bot.set_default_send_options :max_lines => v
      },
      :desc => "Maximum number of IRC lines to send for each message (set to 0 for no limit)")
    Config.register Config::EnumValue.new('send.overlong',
      :values => ['split', 'truncate'], :default => 'split',
      :on_change => Proc.new { |bot, v|
        bot.set_default_send_options :overlong => v.to_sym
      },
      :desc => "When set to split, messages which are too long to fit in a single IRC line are split into multiple lines. When set to truncate, long messages are truncated to fit the IRC line length")
    Config.register Config::StringValue.new('send.split_at',
      :default => '\s+',
      :on_change => Proc.new { |bot, v|
        bot.set_default_send_options :split_at => Regexp.new(v)
      },
      :desc => "A regular expression that should match the split points for overlong messages (see send.overlong)")
    Config.register Config::BooleanValue.new('send.purge_split',
      :default => true,
      :on_change => Proc.new { |bot, v|
        bot.set_default_send_options :purge_split => v
      },
      :desc => "Set to true if the splitting boundary (set in send.split_at) should be removed when splitting overlong messages (see send.overlong)")
    Config.register Config::StringValue.new('send.truncate_text',
      :default => "#{Reverse}...#{Reverse}",
      :on_change => Proc.new { |bot, v|
        bot.set_default_send_options :truncate_text => v.dup
      },
      :desc => "When truncating overlong messages (see send.overlong) or when sending too many lines per message (see send.max_lines) replace the end of the last line with this text")

    @argv = params[:argv]
    @run_dir = params[:run_dir] || Dir.pwd

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
      # * On POSIX systems we prefer ~/.rbot for the effective uid of the process
      # * On Windows (at least the NT versions) we want to put our stuff in the
      #   Application Data folder.
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
    Dir.mkdir("#{botclass}/safe_save") unless File.exist?("#{botclass}/safe_save")

    # Time at which the last PING was sent
    @last_ping = nil
    # Time at which the last line was RECV'd from the server
    @last_rec = nil

    @startup_time = Time.new

    begin
      @config = Config.manager
      @config.bot_associate(self)
    rescue Exception => e
      fatal e
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
      rescue SystemExit
        exit 0
      rescue Exception => e
        warning "Could not background. #{e.pretty_inspect}"
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
        return str.to_s.size
      end
      def STDERR.write(str=nil)
        if str.to_s.match(/:\d+: warning:/)
          warning str, 2
        else
          error str, 2
        end
        return str.to_s.size
      end
    end

    # Set the new logfile and loglevel. This must be done after the daemonizing
    $logger = Logger.new(@logfile, @config['log.keep'], @config['log.max_size']*1024*1024)
    $logger.datetime_format= $dateformat
    $logger.level = @config['log.level']
    $logger.level = $cl_loglevel if defined? $cl_loglevel
    $logger.level = 0 if $debug

    log_session_start

    File.open($opts['pidfile'] || "#{@botclass}/rbot.pid", 'w') do |pf|
      pf << "#{$$}\n"
    end

    @registry = Registry.new self

    @timer = Timer.new
    @save_mutex = Mutex.new
    if @config['core.save_every'] > 0
      @save_timer = @timer.add(@config['core.save_every']) { save }
    else
      @save_timer = nil
    end
    @quit_mutex = Mutex.new

    @logs = Hash.new

    @plugins = nil
    @lang = Language.new(self, @config['core.language'])

    begin
      @auth = Auth::manager
      @auth.bot_associate(self)
      # @auth.load("#{botclass}/botusers.yaml")
    rescue Exception => e
      fatal e
      log_session_end
      exit 2
    end
    @auth.everyone.set_default_permission("*", true)
    @auth.botowner.password= @config['auth.password']

    Dir.mkdir("#{botclass}/plugins") unless File.exist?("#{botclass}/plugins")
    @plugins = Plugins::manager
    @plugins.bot_associate(self)
    setup_plugins_path()

    if @config['server.name']
        debug "upgrading configuration (server.name => server.list)"
        srv_uri = 'irc://' + @config['server.name']
        srv_uri += ":#{@config['server.port']}" if @config['server.port']
        @config.items['server.list'.to_sym].set_string(srv_uri)
        @config.delete('server.name'.to_sym)
        @config.delete('server.port'.to_sym)
        debug "server.list is now #{@config['server.list'].inspect}"
    end

    @socket = Irc::Socket.new(@config['server.list'], @config['server.bindhost'], @config['server.sendq_delay'], @config['server.sendq_burst'], :ssl => @config['server.ssl'])
    @client = Client.new

    @plugins.scan

    # Channels where we are quiet
    # Array of channels names where the bot should be quiet
    # '*' means all channels
    #
    @quiet = []

    @client[:welcome] = proc {|data|
      m = WelcomeMessage.new(self, server, data[:source], data[:target], data[:message])

      irclog "joined server #{@client.server} as #{myself}", "server"

      @plugins.delegate("welcome", m)
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

    # TODO the next two @client should go into rfc2812.rb, probably
    # Since capabs are two-steps processes, server.supports[:capab]
    # should be a three-state: nil, [], [....]
    asked_for = { :"identify-msg" => false }
    @client[:isupport] = proc { |data|
      if server.supports[:capab] and !asked_for[:"identify-msg"]
        sendq "CAPAB IDENTIFY-MSG"
        asked_for[:"identify-msg"] = true
      end
    }
    @client[:datastr] = proc { |data|
      if data[:text] == "IDENTIFY-MSG"
        server.capabilities[:"identify-msg"] = true
      else
        debug "Not handling RPL_DATASTR #{data[:servermessage]}"
      end
    }

    @client[:privmsg] = proc { |data|
      m = PrivMessage.new(self, server, data[:source], data[:target], data[:message])
      # debug "Message source is #{data[:source].inspect}"
      # debug "Message target is #{data[:target].inspect}"
      # debug "Bot is #{myself.inspect}"

      @config['irc.ignore_users'].each { |mask|
        if m.source.matches?(server.new_netmask(mask))
          m.ignored = true
        end
      }

      irclogprivmsg(m)

      @plugins.irc_delegate('privmsg', m) unless m.ignored?
    }
    @client[:notice] = proc { |data|
      message = NoticeMessage.new(self, server, data[:source], data[:target], data[:message])
      # pass it off to plugins that want to hear everything
      @plugins.delegate "listen", message
      @plugins.delegate "notice", message
    }
    @client[:motd] = proc { |data|
      m = MotdMessage.new(self, server, data[:source], data[:target], data[:motd])
      data[:motd].each_line { |line|
        irclog "MOTD: #{line}", "server"
      }
      @plugins.delegate "motd", m
    }
    @client[:nicktaken] = proc { |data|
      new = "#{data[:nick]}_"
      nickchg new
      # If we're setting our nick at connection because our choice was taken,
      # we have to fix our nick manually, because there will be no NICK message
      # to inform us that our nick has been changed.
      if data[:target] == '*'
        debug "setting my connection nick to #{new}"
        nick = new
      end
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
      # debug "Message source is #{data[:source].inspect}"
      # debug "Bot is #{myself.inspect}"
      source = data[:source]
      old = data[:oldnick]
      new = data[:newnick]
      m = NickMessage.new(self, server, source, old, new)
      if source == myself
        debug "my nick is now #{new}"
      end
      data[:is_on].each { |ch|
        irclog "@ #{old} is now known as #{new}", ch
      }
      @plugins.irc_delegate("nick", m)
    }
    @client[:quit] = proc {|data|
      source = data[:source]
      message = data[:message]
      m = QuitMessage.new(self, server, source, source, message)
      data[:was_on].each { |ch|
        irclog "@ Quit: #{source}: #{message}", ch
      }
      @plugins.irc_delegate("quit", m)
    }
    @client[:mode] = proc {|data|
      m = ModeChangeMessage.new(self, server, data[:source], data[:target], data[:modestring])
      m.modes = data[:modes]
      irclog "@ Mode #{data[:modestring]} by #{data[:source]}", data[:target]
      @plugins.delegate "modechange", m
    }
    @client[:join] = proc {|data|
      m = JoinMessage.new(self, server, data[:source], data[:channel], data[:message])
      irclogjoin(m)

      @plugins.irc_delegate("join", m)
      sendq("WHO #{data[:channel]}", data[:channel], 2) if m.address?
    }
    @client[:part] = proc {|data|
      m = PartMessage.new(self, server, data[:source], data[:channel], data[:message])
      irclogpart(m)

      @plugins.irc_delegate("part", m)
    }
    @client[:kick] = proc {|data|
      m = KickMessage.new(self, server, data[:source], data[:target], data[:channel],data[:message])
      irclogkick(m)

      @plugins.irc_delegate("kick", m)
    }
    @client[:invite] = proc {|data|
      m = InviteMessage.new(self, server, data[:source], data[:target], data[:channel])

      @plugins.irc_delegate("invite", m)
    }
    @client[:changetopic] = proc {|data|
      m = TopicMessage.new(self, server, data[:source], data[:channel], data[:topic])
      irclogtopic(m)

      @plugins.irc_delegate("topic", m)
    }
    @client[:topic] = proc { |data|
      irclog "@ Topic is \"#{data[:topic]}\"", data[:channel]
    }
    @client[:topicinfo] = proc { |data|
      channel = data[:channel]
      topic = channel.topic
      irclog "@ Topic set by #{topic.set_by} on #{topic.set_on}", channel
      m = TopicMessage.new(self, server, data[:source], channel, topic)

      @plugins.irc_delegate("topic", m)
    }
    @client[:names] = proc { |data|
      m = NamesMessage.new(self, server, server, data[:channel])
      m.users = data[:users]
      @plugins.delegate "names", m
    }
    @client[:unknown] = proc { |data|
      #debug "UNKNOWN: #{data[:serverstring]}"
      m = UnknownMessage.new(self, server, server, nil, data[:serverstring])
      irclog data[:serverstring], ".unknown"
      @plugins.delegate "unknown_message", m
    }

    set_default_send_options :newlines => @config['send.newlines'].to_sym,
      :join_with => @config['send.join_with'].dup,
      :max_lines => @config['send.max_lines'],
      :overlong => @config['send.overlong'].to_sym,
      :split_at => Regexp.new(@config['send.split_at']),
      :purge_split => @config['send.purge_split'],
      :truncate_text => @config['send.truncate_text'].dup
  end

  def setup_plugins_path
    @plugins.clear_botmodule_dirs
    @plugins.add_botmodule_dir(Config::coredir + "/utils")
    @plugins.add_botmodule_dir(Config::coredir)
    @plugins.add_botmodule_dir("#{botclass}/plugins")

    @config['plugins.path'].each do |_|
        path = _.sub(/^\(default\)/, Config::datadir + '/plugins')
        @plugins.add_botmodule_dir(path)
    end
  end

  def set_default_send_options(opts={})
    # Default send options for NOTICE and PRIVMSG
    unless defined? @default_send_options
      @default_send_options = {
        :queue_channel => nil,      # use default queue channel
        :queue_ring => nil,         # use default queue ring
        :newlines => :split,        # or :join
        :join_with => ' ',          # by default, use a single space
        :max_lines => 0,          # maximum number of lines to send with a single command
        :overlong => :split,        # or :truncate
        # TODO an array of splitpoints would be preferrable for this option:
        :split_at => /\s+/,         # by default, split overlong lines at whitespace
        :purge_split => true,       # should the split string be removed?
        :truncate_text => "#{Reverse}...#{Reverse}"  # text to be appened when truncating
      }
    end
    @default_send_options.update opts unless opts.empty?
    end

  # checks if we should be quiet on a channel
  def quiet_on?(channel)
    return @quiet.include?('*') || @quiet.include?(channel.downcase)
  end

  def set_quiet(channel)
    if channel
      ch = channel.downcase.dup
      @quiet << ch unless @quiet.include?(ch)
    else
      @quiet.clear
      @quiet << '*'
    end
  end

  def reset_quiet(channel)
    if channel
      @quiet.delete channel.downcase
    else
      @quiet.clear
    end
  end

  # things to do when we receive a signal
  def got_sig(sig)
    debug "received #{sig}, queueing quit"
    $interrupted += 1
    quit unless @quit_mutex.locked?
    debug "interrupted #{$interrupted} times"
    if $interrupted >= 3
      debug "drastic!"
      log_session_end
      exit 2
    end
  end

  # connect the bot to IRC
  def connect
    begin
      trap("SIGINT") { got_sig("SIGINT") }
      trap("SIGTERM") { got_sig("SIGTERM") }
      trap("SIGHUP") { got_sig("SIGHUP") }
    rescue ArgumentError => e
      debug "failed to trap signals (#{e.pretty_inspect}): running on Windows?"
    rescue Exception => e
      debug "failed to trap signals: #{e.pretty_inspect}"
    end
    begin
      quit if $interrupted > 0
      @socket.connect
    rescue => e
      raise e.class, "failed to connect to IRC server at #{@socket.server_uri}: " + e
    end
    quit if $interrupted > 0

    realname = @config['irc.name'].clone || 'Ruby bot'
    realname << ' ' + COPYRIGHT_NOTICE if @config['irc.name_copyright']

    @socket.emergency_puts "PASS " + @config['server.password'] if @config['server.password']
    @socket.emergency_puts "NICK #{@config['irc.nick']}\nUSER #{@config['irc.user']} 4 #{@socket.server_uri.host} :#{realname}"
    quit if $interrupted > 0
    myself.nick = @config['irc.nick']
    myself.user = @config['irc.user']
  end

  # begin event handling loop
  def mainloop
    while true
      begin
        quit if $interrupted > 0
        connect

        quit_msg = nil
        while @socket.connected?
          quit if $interrupted > 0

          # Wait for messages and process them as they arrive. If nothing is
          # received, we call the ping_server() method that will PING the
          # server if appropriate, or raise a TimeoutError if no PONG has been
          # received in the user-chosen timeout since the last PING sent.
          if @socket.select(1)
            break unless reply = @socket.gets
            @last_rec = Time.now
            @client.process reply
          else
            ping_server
          end
        end

      # I despair of this. Some of my users get "connection reset by peer"
      # exceptions that ARENT SocketError's. How am I supposed to handle
      # that?
      rescue SystemExit
        log_session_end
        exit 0
      rescue Errno::ETIMEDOUT, Errno::ECONNABORTED, TimeoutError, SocketError => e
        error "network exception: #{e.pretty_inspect}"
        quit_msg = e.to_s
      rescue BDB::Fatal => e
        fatal "fatal bdb error: #{e.pretty_inspect}"
        DBTree.stats
        # Why restart? DB problems are serious stuff ...
        # restart("Oops, we seem to have registry problems ...")
        log_session_end
        exit 2
      rescue Exception => e
        error "non-net exception: #{e.pretty_inspect}"
        quit_msg = e.to_s
      rescue => e
        fatal "unexpected exception: #{e.pretty_inspect}"
        log_session_end
        exit 2
      end

      disconnect(quit_msg)

      log "\n\nDisconnected\n\n"

      quit if $interrupted > 0

      log "\n\nWaiting to reconnect\n\n"
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
  def sendmsg(type, where, original_message, options={})
    opts = @default_send_options.merge(options)

    # For starters, set up appropriate queue channels and rings
    mchan = opts[:queue_channel]
    mring = opts[:queue_ring]
    if mchan
      chan = mchan
    else
      chan = where
    end
    if mring
      ring = mring
    else
      case where
      when User
        ring = 1
      else
        ring = 2
      end
    end

    multi_line = original_message.to_s.gsub(/[\r\n]+/, "\n")
    messages = Array.new
    case opts[:newlines]
    when :join
      messages << [multi_line.gsub("\n", opts[:join_with])]
    when :split
      multi_line.each_line { |line|
        line.chomp!
        next unless(line.size > 0)
        messages << line
      }
    else
      raise "Unknown :newlines option #{opts[:newlines]} while sending #{original_message.inspect}"
    end

    # The IRC protocol requires that each raw message must be not longer
    # than 512 characters. From this length with have to subtract the EOL
    # terminators (CR+LF) and the length of ":botnick!botuser@bothost "
    # that will be prepended by the server to all of our messages.

    # The maximum raw message length we can send is therefore 512 - 2 - 2
    # minus the length of our hostmask.

    max_len = 508 - myself.fullform.size

    # On servers that support IDENTIFY-MSG, we have to subtract 1, because messages
    # will have a + or - prepended
    if server.capabilities[:"identify-msg"]
      max_len -= 1
    end

    # When splitting the message, we'll be prefixing the following string:
    # (e.g. "PRIVMSG #rbot :")
    fixed = "#{type} #{where} :"

    # And this is what's left
    left = max_len - fixed.size

    truncate = opts[:truncate_text]
    truncate = @default_send_options[:truncate_text] if truncate.size > left
    truncate = "" if truncate.size > left

    all_lines = messages.map { |line|
      if line.size < left
        line
      else
        case opts[:overlong]
        when :split
          msg = line.dup
          sub_lines = Array.new
          begin
            sub_lines << msg.slice!(0, left)
            break if msg.empty?
            lastspace = sub_lines.last.rindex(opts[:split_at])
            if lastspace
              msg.replace sub_lines.last.slice!(lastspace, sub_lines.last.size) + msg
              msg.gsub!(/^#{opts[:split_at]}/, "") if opts[:purge_split]
            end
          end until msg.empty?
          sub_lines
        when :truncate
          line.slice(0, left - truncate.size) << truncate
        else
          raise "Unknown :overlong option #{opts[:overlong]} while sending #{original_message.inspect}"
        end
      end
    }.flatten

    if opts[:max_lines] > 0 and all_lines.length > opts[:max_lines]
      lines = all_lines[0...opts[:max_lines]]
      new_last = lines.last.slice(0, left - truncate.size) << truncate
      lines.last.replace(new_last)
    else
      lines = all_lines
    end

    lines.each { |line|
      sendq "#{fixed}#{line}", chan, ring
      log_sent(type, where, line)
    }
  end

  # queue an arbitraty message for the server
  def sendq(message="", chan=nil, ring=0)
    # temporary
    @socket.queue(message, chan, ring)
  end

  # send a notice message to channel/nick +where+
  def notice(where, message, options={})
    return if where.kind_of?(Channel) and quiet_on?(where)
    sendmsg "NOTICE", where, message, options
  end

  # say something (PRIVMSG) to channel/nick +where+
  def say(where, message, options={})
    return if where.kind_of?(Channel) and quiet_on?(where)
    sendmsg "PRIVMSG", where, message, options
  end

  def ctcp_notice(where, command, message, options={})
    return if where.kind_of?(Channel) and quiet_on?(where)
    sendmsg "NOTICE", where, "\001#{command} #{message}\001", options
  end

  def ctcp_say(where, command, message, options={})
    return if where.kind_of?(Channel) and quiet_on?(where)
    sendmsg "PRIVMSG", where, "\001#{command} #{message}\001", options
  end

  # perform a CTCP action with message +message+ to channel/nick +where+
  def action(where, message, options={})
    ctcp_say(where, 'ACTION', message, options)
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
    if where.class <= Server
      where_str = "server"
    else
      where_str = where.downcase.gsub(/[:!?$*()\/\\<>|"']/, "_")
    end
    unless(@logs.has_key?(where_str))
      @logs[where_str] = File.new("#{@botclass}/logs/#{where_str}", "a")
      @logs[where_str].sync = true
    end
    @logs[where_str].puts "[#{stamp}] #{message}"
    #debug "[#{stamp}] <#{where}> #{message}"
  end

  # set topic of channel +where+ to +topic+
  def topic(where, topic)
    sendq "TOPIC #{where} :#{topic}", where, 2
  end

  def disconnect(message=nil)
    message = @lang.get("quit") if (!message || message.empty?)
    if @socket.connected?
      begin
        debug "Clearing socket"
        @socket.clearq
        debug "Sending quit message"
        @socket.emergency_puts "QUIT :#{message}"
        debug "Flushing socket"
        @socket.flush
      rescue SocketError => e
        error "error while disconnecting socket: #{e.pretty_inspect}"
      end
      debug "Shutting down socket"
      @socket.shutdown
    end
    debug "Logging quits"
    server.channels.each { |ch|
      irclog "@ quit (#{message})", ch
    }
    stop_server_pings
    @client.reset
  end

  # disconnect from the server and cleanup all plugins and modules
  def shutdown(message=nil)
    @quit_mutex.synchronize do
      debug "Shutting down: #{message}"
      ## No we don't restore them ... let everything run through
      # begin
      #   trap("SIGINT", "DEFAULT")
      #   trap("SIGTERM", "DEFAULT")
      #   trap("SIGHUP", "DEFAULT")
      # rescue => e
      #   debug "failed to restore signals: #{e.inspect}\nProbably running on windows?"
      # end
      debug "\tdisconnecting..."
      disconnect(message)
      debug "\tstopping timer..."
      @timer.stop
      debug "\tsaving ..."
      save
      debug "\tcleaning up ..."
      @save_mutex.synchronize do
        @plugins.cleanup
      end
      # debug "\tstopping timers ..."
      # @timer.stop
      # debug "Closing registries"
      # @registry.close
      debug "\t\tcleaning up the db environment ..."
      DBTree.cleanup_env
      log "rbot quit (#{message})"
    end
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
  def restart(message=nil)
    message = "restarting, back in #{@config['server.reconnect_wait']}..." if (!message || message.empty?)
    shutdown(message)
    sleep @config['server.reconnect_wait']
    begin
      # now we re-exec
      # Note, this fails on Windows
      debug "going to exec #{$0} #{@argv.inspect} from #{@run_dir}"
      Dir.chdir(@run_dir)
      exec($0, *@argv)
    rescue Errno::ENOENT
      exec("ruby", *(@argv.unshift $0))
    rescue Exception => e
      $interrupted += 1
      raise e
    end
  end

  # call the save method for all of the botmodules
  def save
    @save_mutex.synchronize do
      @plugins.save
      DBTree.cleanup_logs
    end
  end

  # call the rescan method for all of the botmodules
  def rescan
    debug "\tstopping timer..."
    @timer.stop
    @save_mutex.synchronize do
      @lang.rescan
      @plugins.rescan
    end
    @timer.start
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

  # kicking a user
  def kick(channel, user, msg)
    sendq "KICK #{channel} #{user} :#{msg}", channel, 2
  end

  # m::     message asking for help
  # topic:: optional topic help is requested for
  # respond to online help requests
  def help(topic=nil)
    topic = nil if topic == ""
    case topic
    when nil
      helpstr = _("help topics: ")
      helpstr += @plugins.helptopics
      helpstr += _(" (help <topic> for more info)")
    else
      unless(helpstr = @plugins.help(topic))
        helpstr = _("no help for topic %{topic}") % { :topic => topic }
      end
    end
    return helpstr
  end

  # returns a string describing the current status of the bot (uptime etc)
  def status
    secs_up = Time.new - @startup_time
    uptime = Utils.secs_to_string secs_up
    # return "Uptime #{uptime}, #{@plugins.length} plugins active, #{@registry.length} items stored in registry, #{@socket.lines_sent} lines sent, #{@socket.lines_received} received."
    return (_("Uptime %{up}, %{plug} plugins active, %{sent} lines sent, %{recv} received.") %
             {
               :up => uptime, :plug => @plugins.length,
               :sent => @socket.lines_sent, :recv => @socket.lines_received
             })
  end

  # We want to respond to a hung server in a timely manner. If nothing was received
  # in the user-selected timeout and we haven't PINGed the server yet, we PING
  # the server. If the PONG is not received within the user-defined timeout, we
  # assume we're in ping timeout and act accordingly.
  def ping_server
    act_timeout = @config['server.ping_timeout']
    return if act_timeout <= 0
    now = Time.now
    if @last_rec && now > @last_rec + act_timeout
      if @last_ping.nil?
        # No previous PING pending, send a new one
        sendq "PING :rbot"
        @last_ping = Time.now
      else
        diff = now - @last_ping
        if diff > act_timeout
          debug "no PONG from server in #{diff} seconds, reconnecting"
          # the actual reconnect is handled in the main loop:
          raise TimeoutError, "no PONG from server in #{diff} seconds"
        end
      end
    end
  end

  def stop_server_pings
    # cancel previous PINGs and reset time of last RECV
    @last_ping = nil
    @last_rec = nil
  end

  private

  def irclogprivmsg(m)
    if(m.action?)
      if(m.private?)
        irclog "* [#{m.source}(#{m.sourceaddress})] #{m.logmessage}", m.source
      else
        irclog "* #{m.source} #{m.logmessage}", m.target
      end
    else
      if(m.public?)
        irclog "<#{m.source}> #{m.logmessage}", m.target
      else
        irclog "[#{m.source}(#{m.sourceaddress})] #{m.logmessage}", m.source
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
        else
          irclog "[-=#{where}=-] #{message}", where
        end
      when "PRIVMSG"
        case where
        when Channel
          irclog "<#{myself}> #{message}", where
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
      irclog "@ #{m.source} joined channel #{m.channel}", m.channel
    end
  end

  def irclogpart(m)
    if(m.address?)
      debug "left channel #{m.channel}"
      irclog "@ Left channel #{m.channel} (#{m.logmessage})", m.channel
    else
      irclog "@ #{m.source} left channel #{m.channel} (#{m.logmessage})", m.channel
    end
  end

  def irclogkick(m)
    if(m.address?)
      debug "kicked from channel #{m.channel}"
      irclog "@ You have been kicked from #{m.channel} by #{m.source} (#{m.logmessage})", m.channel
    else
      irclog "@ #{m.target} has been kicked from #{m.channel} by #{m.source} (#{m.logmessage})", m.channel
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
