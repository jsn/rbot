# Copyright (C) 2002 Tom Gilbert.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to
# deal in the Software without restriction, including without limitation the
# rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
# sell copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies of the Software and its documentation and acknowledgment shall be
# given in the documentation and software packages that this Software was
# used.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
# THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
# IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
# CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

require 'thread'

require 'rbot/rfc2812'
require 'rbot/keywords'
require 'rbot/config'
require 'rbot/ircsocket'
require 'rbot/auth'
require 'rbot/timer'
require 'rbot/plugins'
require 'rbot/channel'
require 'rbot/utils'
require 'rbot/message'
require 'rbot/language'
require 'rbot/dbhash'
require 'rbot/registry'

module Irc

# Main bot class, which receives messages, handles them or passes them to
# plugins, and stores runtime data
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

  # bot's configured addressing prefixes
  attr_reader :addressing_prefixes

  # channel info for channels the bot is in
  attr_reader :channels

  # bot's object registry, plugins get an interface to this for persistant
  # storage (hash interface tied to a bdb file, plugins use Accessors to store
  # and restore objects in their own namespaces.)
  attr_reader :registry

  # create a new IrcBot with botclass +botclass+
  def initialize(botclass)
    @botclass = botclass.gsub(/\/$/, "")
    @startup_time = Time.new
    
    Dir.mkdir("#{botclass}") if(!File.exist?("#{botclass}"))
    Dir.mkdir("#{botclass}/logs") if(!File.exist?("#{botclass}/logs"))

    @config = Irc::BotConfig.new(self)
    @timer = Timer::Timer.new
    @registry = BotRegistry.new self
    @timer.add(@config["SAVE_EVERY"].to_i) { save }
    @channels = Hash.new
    @logs = Hash.new
    
    @lang = Irc::Language.new(@config["LANGUAGE"])
    @keywords = Irc::Keywords.new(self)
    @auth = Irc::IrcAuth.new(self)
    @plugins = Irc::Plugins.new(self, ["#{botclass}/plugins"])
    @socket = Irc::IrcSocket.new(@config["SERVER"], @config["PORT"], @config["HOST"], @config["SENDQ_DELAY"], @config["SENDQ_BURST"])
    @nick = @config["NICK"]
    @server_password = @config["SERVER_PASSWORD"]
    if @config["ADDRESS_PREFIX"]
      @addressing_prefixes = @config["ADDRESS_PREFIX"].split(" ")
    else
      @addressing_prefixes = Array.new
    end
    
    @client = Irc::IrcClient.new
    @client["PRIVMSG"] = proc { |data|
      message = PrivMessage.new(self, data["SOURCE"], data["TARGET"], data["MESSAGE"])
      onprivmsg(message)
    }
    @client["NOTICE"] = proc { |data|
      message = NoticeMessage.new(self, data["SOURCE"], data["TARGET"], data["MESSAGE"])
      # pass it off to plugins that want to hear everything
      @plugins.delegate "listen", message
    }
    @client["MOTD"] = proc { |data|
      data['MOTD'].each_line { |line|
        log "MOTD: #{line}", "server"
      }
    }
    @client["NICKTAKEN"] = proc { |data| 
      nickchg "#{@nick}_"
    }
    @client["BADNICK"] = proc {|data| 
      puts "WARNING, bad nick (#{data['NICK']})"
    }
    @client["PING"] = proc {|data|
      # (jump the queue for pongs)
      @socket.puts "PONG #{data['PINGID']}"
    }
    @client["NICK"] = proc {|data|
      sourcenick = data["SOURCENICK"]
      nick = data["NICK"]
      m = NickMessage.new(self, data["SOURCE"], data["SOURCENICK"], data["NICK"])
      if(sourcenick == @nick)
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
    @client["QUIT"] = proc {|data|
      source = data["SOURCE"]
      sourcenick = data["SOURCENICK"]
      sourceurl = data["SOURCEADDRESS"]
      message = data["MESSAGE"]
      m = QuitMessage.new(self, data["SOURCE"], data["SOURCENICK"], data["MESSAGE"])
      if(data["SOURCENICK"] =~ /#{@nick}/i)
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
    @client["MODE"] = proc {|data|
      source = data["SOURCE"]
      sourcenick = data["SOURCENICK"]
      sourceurl = data["SOURCEADDRESS"]
      channel = data["CHANNEL"]
      targets = data["TARGETS"]
      modestring = data["MODESTRING"]
      log "@ Mode #{modestring} #{targets} by #{sourcenick}", channel
    }
    @client["WELCOME"] = proc {|data|
      log "joined server #{data['SOURCE']} as #{data['NICK']}", "server"
      debug "I think my nick is #{@nick}, server thinks #{data['NICK']}"
      if data['NICK'] && data['NICK'].length > 0
        @nick = data['NICK']
      end
      if(@config["QUSER"])
        puts "authing with Q using  #{@config["QUSER"]} #{@config["QAUTH"]}"
        @socket.puts "PRIVMSG Q@CServe.quakenet.org :auth #{@config["QUSER"]} #{@config["QAUTH"]}"
      end

      if(@config["JOIN_CHANNELS"])
        @config["JOIN_CHANNELS"].split(", ").each {|c|
          puts "autojoining channel #{c}"
          if(c =~ /^(\S+)\s+(\S+)$/i)
            join $1, $2
          else
            join c if(c)
          end
        }
      end
    }
    @client["JOIN"] = proc {|data|
      m = JoinMessage.new(self, data["SOURCE"], data["CHANNEL"], data["MESSAGE"])
      onjoin(m)
    }
    @client["PART"] = proc {|data|
      m = PartMessage.new(self, data["SOURCE"], data["CHANNEL"], data["MESSAGE"])
      onpart(m)
    }
    @client["KICK"] = proc {|data|
      m = KickMessage.new(self, data["SOURCE"], data["TARGET"],data["CHANNEL"],data["MESSAGE"]) 
      onkick(m)
    }
    @client["INVITE"] = proc {|data|
      if(data["TARGET"] =~ /^#{@nick}$/i)
        join data["CHANNEL"] if (@auth.allow?("join", data["SOURCE"], data["SOURCENICK"]))
      end
    }
    @client["CHANGETOPIC"] = proc {|data|
      channel = data["CHANNEL"]
      sourcenick = data["SOURCENICK"]
      topic = data["TOPIC"]
      timestamp = data["UNIXTIME"] || Time.now.to_i
      if(sourcenick == @nick)
        log "@ I set topic \"#{topic}\"", channel
      else
        log "@ #{sourcenick} set topic \"#{topic}\"", channel
      end
      m = TopicMessage.new(self, data["SOURCE"], data["CHANNEL"], timestamp, data["TOPIC"])

      ontopic(m)
      @plugins.delegate("topic", m)
      @plugins.delegate("listen", m)
    }
    @client["TOPIC"] = @client["TOPICINFO"] = proc {|data|
      channel = data["CHANNEL"]
      m = TopicMessage.new(self, data["SOURCE"], data["CHANNEL"], data["UNIXTIME"], data["TOPIC"])
        ontopic(m)
    }
    @client["NAMES"] = proc {|data|
      channel = data["CHANNEL"]
      users = data["USERS"]
      unless(@channels[channel])
        puts "bug: got names for channel '#{channel}' I didn't think I was in\n"
        exit 2
      end
      @channels[channel].users.clear
      users.each {|u|
        @channels[channel].users[u[0].sub(/^[@&~+]/, '')] = ["mode", u[1]]
      }
    }
    @client["UNKNOWN"] = proc {|data|
      debug "UNKNOWN: #{data['SERVERSTRING']}"
    }
  end

  # connect the bot to IRC
  def connect
    trap("SIGTERM") { quit }
    trap("SIGHUP") { quit }
    trap("SIGINT") { quit }
    begin
      @socket.connect
      rescue => e
      raise "failed to connect to IRC server at #{@config['SERVER']} #{@config['PORT']}: " + e
    end
    @socket.puts "PASS " + @server_password if @server_password
    @socket.puts "NICK #{@nick}\nUSER #{@config['USER']} 4 #{@config['SERVER']} :Ruby bot. (c) Tom Gilbert"
  end

  # begin event handling loop
  def mainloop
    socket_timeout = 0.2
    reconnect_wait = 5
    
    while true
      connect
      
      begin
        while true
          if @socket.select socket_timeout
            break unless reply = @socket.gets
            @client.process reply
          end
          @timer.tick
        end
      rescue => e
        puts "connection closed: #{e}"
        puts e.backtrace.join("\n")
      end
      
      puts "disconnected"
      @channels.clear
      @socket.clearq
      
      puts "waiting to reconnect"
      sleep reconnect_wait
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
    message.chomp!
    stamp = Time.now.strftime("%Y/%m/%d %H:%M:%S")
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
  
  # message:: optional IRC quit message
  # quit IRC, shutdown the bot
  def quit(message=nil)
    trap("SIGTERM", "DEFAULT")
    trap("SIGHUP", "DEFAULT")
    trap("SIGINT", "DEFAULT")
    message = @lang.get("quit") if (!message || message.length < 1)
    @socket.clearq
    save
    @plugins.cleanup
    @channels.each_value {|v|
      log "@ quit (#{message})", v.name
    }
    @socket.puts "QUIT :#{message}"
    @socket.flush
    @socket.shutdown
    @registry.close
    puts "rbot quit (#{message})"
    exit 0
  end

  # call the save method for bot's config, keywords, auth and all plugins
  def save
    @registry.flush
    @config.save
    @keywords.save
    @auth.save
    @plugins.save
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

  private

  # handle help requests for "core" topics
  def corehelp(topic="")
    case topic
      when "quit"
        return "quit [<message>] => quit IRC with message <message>"
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
      when "topic"
        return "topic <channel> <message> => set topic of <channel> to <message>"
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
        return "Core help topics: quit, join, part, hide, save, rescan, nick, say, action, topic, quiet, talk, version, botsnack, hello"
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
        when (/^hide$/i)
          join 0 if(@auth.allow?("join", m.source, m.replyto))
        when (/^save$/i)
          if(@auth.allow?("config", m.source, m.replyto))
            okay m.replyto
            save
          end
        when (/^nick\s+(\S+)$/i)
          nickchg($1) if(@auth.allow?("nick", m.source, m.replyto))
        when (/^say\s+(\S+)\s+(.*)$/i)
          say $1, $2 if(@auth.allow?("say", m.source, m.replyto))
        when (/^action\s+(\S+)\s+(.*)$/i)
          action $1, $2 if(@auth.allow?("say", m.source, m.replyto))
        when (/^topic\s+(\S+)\s+(.*)$/i)
          topic $1, $2 if(@auth.allow?("topic", m.source, m.replyto))
        when (/^mode\s+(\S+)\s+(\S+)\s+(.*)$/i)
          mode $1, $2, $3 if(@auth.allow?("mode", m.source, m.replyto))
        when (/^ping$/i)
          say m.replyto, "pong"
        when (/^rescan$/i)
          if(@auth.allow?("config", m.source, m.replyto))
            okay m.replyto
            rescan
          end
        when (/^quiet$/i)
          if(auth.allow?("talk", m.source, m.replyto))
            say m.replyto, @lang.get("okay")
            @channels.each_value {|c| c.quiet = true }
          end
        when (/^quiet in (\S+)$/i)
          where = $1
          if(auth.allow?("talk", m.source, m.replyto))
            say m.replyto, @lang.get("okay")
            where.gsub!(/^here$/, m.target) if m.public?
            @channels[where].quiet = true if(@channels.has_key?(where))
          end
        when (/^talk$/i)
          if(auth.allow?("talk", m.source, m.replyto))
            @channels.each_value {|c| c.quiet = false }
            okay m.replyto
          end
        when (/^talk in (\S+)$/i)
          where = $1
          if(auth.allow?("talk", m.source, m.replyto))
            where.gsub!(/^here$/, m.target) if m.public?
            @channels[where].quiet = false if(@channels.has_key?(where))
            okay m.replyto
          end
        # TODO break this out into an options module
        when (/^options get sendq_delay$/i)
          if auth.allow?("config", m.source, m.replyto)
            m.reply "options->sendq_delay = #{@socket.get_sendq}"
          end
        when (/^options get sendq_burst$/i)
          if auth.allow?("config", m.source, m.replyto)
            m.reply "options->sendq_burst = #{@socket.get_maxburst}"
          end
        when (/^options set sendq_burst (.*)$/i)
          num = $1.to_i
          if auth.allow?("config", m.source, m.replyto)
            @socket.set_maxburst(num)
            @config["SENDQ_BURST"] = num
            okay m.replyto
          end
        when (/^options set sendq_delay (.*)$/i)
          freq = $1.to_f
          if auth.allow?("config", m.source, m.replyto)
            @socket.set_sendq(freq)
            @config["SENDQ_DELAY"] = freq
            okay m.replyto
          end
        when (/^status$/i)
          m.reply status if auth.allow?("status", m.source, m.replyto)
        when (/^registry stats$/i)
          if auth.allow?("config", m.source, m.replyto)
            m.reply @registry.stat.inspect
          end
        when (/^(version)|(introduce yourself)$/i)
          say m.replyto, "I'm a v. #{$version} rubybot, (c) Tom Gilbert - http://linuxbrit.co.uk/rbot/"
        when (/^help(?:\s+(.*))?$/i)
          say m.replyto, help($1)
        when (/^(botsnack|ciggie)$/i)
          say m.replyto, @lang.get("thanks_X") % m.sourcenick if(m.public?)
          say m.replyto, @lang.get("thanks") if(m.private?)
        when (/^(hello|howdy|hola|salut|bonjour|sup|niihau|hey|hi(\W|$)|yo(\W|$)).*/i)
          say m.replyto, @lang.get("hello_X") % m.sourcenick if(m.public?)
          say m.replyto, @lang.get("hello") if(m.private?)
        else
          delegate_privmsg(m)
      end
    else
      # stuff to handle when not addressed
      case m.message
        when (/^\s*(hello|howdy|hola|salut|bonjour|sup|niihau|hey|hi(\W|$)|yo(\W|$))\s+#{@nick}$/i)
          say m.replyto, @lang.get("hello_X") % m.sourcenick
        when (/^#{@nick}!*$/)
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
      log "@ Joined channel #{m.channel}", m.channel
      puts "joined channel #{m.channel}"
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
      log "@ Left channel #{m.channel} (#{m.message})", m.channel
      @channels.delete(m.channel)
      puts "left channel #{m.channel}"
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
      @channels.delete(m.channel)
      log "@ You have been kicked from #{m.channel} by #{m.sourcenick} (#{m.message})", m.channel
      puts "kicked from channel #{m.channel}"
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

	puts @channels[m.channel].topic
  end

  def status
    secs_up = Time.new - @startup_time
    uptime = Utils.secs_to_string secs_up
    return "Uptime #{uptime}, #{@plugins.length} plugins active, #{@registry.length} items stored in registry, #{@socket.lines_sent} lines sent, #{@socket.lines_received} received."
  end

  # delegate a privmsg to auth, keyword or plugin handlers
  def delegate_privmsg(message)
    [@auth, @plugins, @keywords].each {|m|
      break if m.privmsg(message)
    }
  end

end

end
