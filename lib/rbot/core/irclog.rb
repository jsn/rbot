#-- vim:sw=2:et
#++
#
# :title: rbot IRC logging facilities
#
# Author:: Giuseppe "Oblomov" Bilotta <giuseppe.bilotta@gmail.com>

class IrcLogModule < CoreBotModule

  Config.register Config::IntegerValue.new('irclog.max_open_files',
    :default => 20, :validate => Proc.new { |v| v > 0 },
    :desc => "Maximum number of irclog files to keep open at any one time.")
  Config.register Config::ArrayValue.new('irclog.no_log',
    :default => [], :on_change => Proc.new { |bot, v|
      bot.plugins.delegate 'event_irclog_list_changed', v, bot.config['irclog.do_log']
    },
    :desc => "List of channels and nicks for which logging is disabled. IRC patterns can be used too.")
  Config.register Config::ArrayValue.new('irclog.do_log',
    :default => [], :on_change => Proc.new { |bot, v|
      bot.plugins.delegate 'event_irclog_list_changed', bot.config['irclog.no_log'], v
    },
    :desc => "List of channels and nicks for which logging is enabled. IRC patterns can be used too. This can be used to override wide patters in irclog.no_log")
  Config.register Config::StringValue.new('irclog.filename_format',
    :default => '%%{where}', :requires_rescan => true,
    :desc => "filename pattern for the IRC log. You can put typical strftime keys such as %Y for year and %m for month, plus the special %%{where} key for location (channel name or user nick)")
  Config.register Config::StringValue.new('irclog.timestamp_format',
    :default => '[%Y/%m/%d %H:%M:%S]', :requires_rescan => true,
    :desc => "timestamp pattern for the IRC log, using typical strftime keys")

  attr :nolog_rx, :dolog_rx
  def initialize
    super
    @queue = Queue.new
    @thread = Thread.new { loggers_thread }
    @logs = Hash.new
    logdir = @bot.path 'logs'
    Dir.mkdir(logdir) unless File.exist?(logdir)
    # TODO what shall we do if the logdir couldn't be created? (e.g. it existed as a file)
    event_irclog_list_changed(@bot.config['irclog.no_log'], @bot.config['irclog.do_log'])
    @fn_format = @bot.config['irclog.filename_format']
  end

  def can_log_on(where)
    return true if @dolog_rx and where.match @dolog_rx
    return false if @nolog_rx and where.match @nolog_rx
    return true
  end

  def timestamp(time)
    return time.strftime @bot.config['irclog.timestamp_format']
  end

  def event_irclog_list_changed(nolist, dolist)
    @nolog_rx = nolist.empty? ? nil : Regexp.union(*(nolist.map { |r| r.to_irc_regexp }))
    debug "no log: #{@nolog_rx}"
    @dolog_rx = dolist.empty? ? nil : Regexp.union(*(dolist.map { |r| r.to_irc_regexp }))
    debug "do log: #{@dolog_rx}"
    @logs.inject([]) { |ar, kv|
      ar << kv.first unless can_log_on(kv.first)
      ar
    }.each { |w| logfile_close(w, 'logging disabled here') }
  end

  def logfile_close(where_str, reason = 'unknown reason')
    f = @logs.delete(where_str) or return
    stamp = timestamp(Time.now)
    f[1].puts "#{stamp} @ Log closed by #{@bot.myself.nick} (#{reason})"
    f[1].close
  end

  # log IRC-related message +message+ to a file determined by +where+.
  # +where+ can be a channel name, or a nick for private message logging
  def irclog(message, where="server")
    @queue.push [message, where]
  end

  def cleanup
    @queue << nil
    @thread.join
    @thread = nil
  end

  def sent(m)
    case m
    when NoticeMessage
      irclog "-#{m.source}- #{m.message}", m.target
    when PrivMessage
      logtarget = who = m.target
      if m.ctcp
        case m.ctcp.intern
        when :ACTION
          irclog "* #{m.source} #{m.logmessage}", logtarget
        when :VERSION
          irclog "@ #{m.source} asked #{who} about version info", logtarget
        when :SOURCE
          irclog "@ #{m.source} asked #{who} about source info", logtarget
        when :PING
          irclog "@ #{m.source} pinged #{who}", logtarget
        when :TIME
          irclog "@ #{m.source} asked #{who} what time it is", logtarget
        else
          irclog "@ #{m.source} asked #{who} about #{[m.ctcp, m.message].join(' ')}", logtarget
        end
      else
        irclog "<#{m.source}> #{m.logmessage}", logtarget
      end
    when QuitMessage
      m.was_on.each { |ch|
        irclog "@ quit (#{m.message})", ch
      }
    end
  end

  def welcome(m)
    irclog "joined server #{m.server} as #{m.target}", "server"
  end

  def listen(m)
    case m
    when PrivMessage
      method = 'log_message'
    else
      method = 'log_' + m.class.name.downcase.match(/^irc::(\w+)message$/).captures.first
    end
    if self.respond_to?(method)
      self.__send__(method, m)
    else
      warning "unhandled logging for #{m.pretty_inspect} (no such method #{method})"
      unknown_message(m)
    end
  end

  def log_message(m)
    if m.ctcp
      who = m.private? ? "me" : m.target
      logtarget = m.private? ? m.source : m.target
      case m.ctcp.intern
      when :ACTION
        if m.public?
          irclog "* #{m.source} #{m.logmessage}", m.target
        else
          irclog "* #{m.source}(#{m.sourceaddress}) #{m.logmessage}", m.source
        end
      when :VERSION
        irclog "@ #{m.source} asked #{who} about version info", logtarget
      when :SOURCE
        irclog "@ #{m.source} asked #{who} about source info", logtarget
      when :PING
        irclog "@ #{m.source} pinged #{who}", logtarget
      when :TIME
        irclog "@ #{m.source} asked #{who} what time it is", logtarget
      else
        irclog "@ #{m.source} asked #{who} about #{[m.ctcp, m.message].join(' ')}", logtarget
      end
    else
      if m.public?
        irclog "<#{m.source}> #{m.logmessage}", m.target
      else
        irclog "<#{m.source}(#{m.sourceaddress})> #{m.logmessage}", m.source
      end
    end
  end

  def log_notice(m)
    if m.private?
      irclog "-#{m.source}(#{m.sourceaddress})- #{m.logmessage}", m.source
    else
      irclog "-#{m.source}- #{m.logmessage}", m.target
    end
  end

  def motd(m)
    m.message.each_line { |line|
      irclog "MOTD: #{line}", "server"
    }
  end

  def log_nick(m)
    (m.is_on & @bot.myself.channels).each { |ch|
      irclog "@ #{m.oldnick} is now known as #{m.newnick}", ch
    }
  end

  def log_quit(m)
    (m.was_on & @bot.myself.channels).each { |ch|
      irclog "@ Quit: #{m.source}: #{m.logmessage}", ch
    }
  end

  def modechange(m)
    irclog "@ Mode #{m.logmessage} by #{m.source}", m.target
  end

  def log_join(m)
    if m.address?
      debug "joined channel #{m.channel}"
      irclog "@ Joined channel #{m.channel}", m.channel
    else
      irclog "@ #{m.source} joined channel #{m.channel}", m.channel
    end
  end

  def log_part(m)
    if(m.address?)
      debug "left channel #{m.channel}"
      irclog "@ Left channel #{m.channel} (#{m.logmessage})", m.channel
    else
      irclog "@ #{m.source} left channel #{m.channel} (#{m.logmessage})", m.channel
    end
  end

  def log_kick(m)
    if(m.address?)
      debug "kicked from channel #{m.channel}"
      irclog "@ You have been kicked from #{m.channel} by #{m.source} (#{m.logmessage})", m.channel
    else
      irclog "@ #{m.target} has been kicked from #{m.channel} by #{m.source} (#{m.logmessage})", m.channel
    end
  end

  # def log_invite(m)
  #   # TODO
  # end

  def log_topic(m)
    case m.info_or_set
    when :set
      if m.source == @bot.myself
        irclog "@ I set topic \"#{m.topic}\"", m.channel
      else
        irclog "@ #{m.source} set topic \"#{m.topic}\"", m.channel
      end
    when :info
      topic = m.channel.topic
      irclog "@ Topic is \"#{m.topic}\"", m.channel
      irclog "@ Topic set by #{topic.set_by} on #{topic.set_on}", m.channel
    end
  end

  # def names(m)
  #   # TODO
  # end

  def unknown_message(m)
    irclog m.logmessage, ".unknown"
  end

  def logfilepath(where_str, now)
    @bot.path('logs', now.strftime(@fn_format) % { :where => where_str })
  end

  protected
  def loggers_thread
    ls = nil
    debug 'loggers_thread starting'
    while ls = @queue.pop
      message, where = ls
      message = message.chomp
      now = Time.now
      stamp = timestamp(now)
      if where.class <= Server
        where_str = "server"
      else
        where_str = where.downcase.gsub(/[:!?$*()\/\\<>|"']/, "_")
      end
      return unless can_log_on(where_str)

      # close the previous logfile if we're rotating
      if @logs.has_key? where_str
        fp = logfilepath(where_str, now)
        logfile_close(where_str, 'log rotation') if fp != @logs[where_str][1].path
      end

      # (re)open the logfile if necessary
      unless @logs.has_key? where_str
        if @logs.size > @bot.config['irclog.max_open_files']
          @logs.keys.sort do |a, b|
            @logs[a][0] <=> @logs[b][0]
          end.slice(0, @logs.size - @bot.config['irclog.max_open_files']).each do |w|
            logfile_close w, "idle since #{@logs[w][0]}"
          end
        end
        fp = logfilepath(where_str, now)
        begin
          dir = File.dirname(fp)
          # first of all, we check we're not trying to build a directory structure
          # where one of the components exists already as a file, so we
          # backtrack along dir until we come across the topmost existing name.
          # If it's a file, we rename to filename.old.filedate
          up = dir.dup
          until File.exist? up
            up.replace File.dirname up
          end
          unless File.directory? up
            backup = up.dup
            backup << ".old." << File.atime(up).strftime('%Y%m%d%H%M%S')
            debug "#{up} is not a directory! renaming to #{backup}"
            File.rename(up, backup)
          end
          FileUtils.mkdir_p(dir)
          # conversely, it may happen that fp exists and is a directory, in
          # which case we rename the directory instead
          if File.directory? fp
            backup = fp.dup
            backup << ".old." << File.atime(fp).strftime('%Y%m%d%H%M%S')
            debug "#{fp} is not a file! renaming to #{backup}"
            File.rename(fp, backup)
          end
          # it should be fine to create the file now
          f = File.new(fp, "a")
          f.sync = true
          f.puts "#{stamp} @ Log started by #{@bot.myself.nick}"
        rescue Exception => e
          error e
          next
        end
        @logs[where_str] = [now, f]
      end
      @logs[where_str][1].puts "#{stamp} #{message}"
      @logs[where_str][0] = now
      #debug "#{stamp} <#{where}> #{message}"
    end
    @logs.keys.each { |w| logfile_close(w, 'rescan or shutdown') }
    debug 'loggers_thread terminating'
  end
end

ilm = IrcLogModule.new
ilm.priority = -1

