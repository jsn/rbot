#-- vim:sw=2:et
#++
#
# :title: rbot IRC logging facilities
#
# Author:: Giuseppe "Oblomov" Bilotta <giuseppe.bilotta@gmail.com>
# Copyright:: (C) 2008 Giuseppe Bilotta
# License:: GPL v2

class IrcLogModule < CoreBotModule

  MAX_OPEN_FILES = 20 # XXX: maybe add a config value
  
  def initialize
    super
    @logs = Hash.new
    Dir.mkdir("#{@bot.botclass}/logs") unless File.exist?("#{@bot.botclass}/logs")
  end

  def logfile_close(where_str, reason = 'unknown reason')
    f = @logs.delete(where_str) or return
    stamp = Time.now.strftime '%Y/%m/%d %H:%M:%S'
    f[1].puts "[#{stamp}] @ Log closed by #{@bot.myself.nick} (#{reason})"
    f[1].close
  end

  # log IRC-related message +message+ to a file determined by +where+.
  # +where+ can be a channel name, or a nick for private message logging
  def irclog(message, where="server")
    message = message.chomp
    now = Time.now
    stamp = now.strftime("%Y/%m/%d %H:%M:%S")
    if where.class <= Server
      where_str = "server"
    else
      where_str = where.downcase.gsub(/[:!?$*()\/\\<>|"']/, "_")
    end
    unless @logs.has_key? where_str
      if @logs.size > MAX_OPEN_FILES
        @logs.keys.sort do |a, b|
          @logs[a][0] <=> @logs[b][0]
        end.slice(0, @logs.size - MAX_OPEN_FILES).each do |w|
          logfile_close w, "idle since #{@logs[w][0]}"
        end
      end
      f = File.new("#{@bot.botclass}/logs/#{where_str}", "a")
      f.sync = true
      f.puts "[#{stamp}] @ Log started by #{@bot.myself.nick}"
      @logs[where_str] = [now, f]
    end
    @logs[where_str][1].puts "[#{stamp}] #{message}"
    @logs[where_str][0] = now
    #debug "[#{stamp}] <#{where}> #{message}"
  end

  def sent(m)
    case m
    when NoticeMessage
      irclog "-#{m.source}- #{m.message}", m.target
    when PrivMessage
      irclog "<#{m.source}> #{m.message}", m.target
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
    m.is_on.each { |ch|
      irclog "@ #{m.oldnick} is now known as #{m.newnick}", ch
    }
  end

  def log_quit(m)
    m.was_on.each { |ch|
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
end

ilm = IrcLogModule.new
ilm.priority = -1

