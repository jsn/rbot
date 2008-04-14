#-- vim:sw=2:et
#++
#
# :title: rbot IRC logging facilities
#
# Author:: Giuseppe "Oblomov" Bilotta <giuseppe.bilotta@gmail.com>
# Copyright:: (C) 2008 Giuseppe Bilotta
# License:: GPL v2

class IrcLogModule < CoreBotModule
  
  def initialize
    super
    @logs = Hash.new
    Dir.mkdir("#{@bot.botclass}/logs") unless File.exist?("#{@bot.botclass}/logs")
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
      @logs[where_str] = File.new("#{@bot.botclass}/logs/#{where_str}", "a")
      @logs[where_str].sync = true
    end
    @logs[where_str].puts "[#{stamp}] #{message}"
    #debug "[#{stamp}] <#{where}> #{message}"
  end

  def sent(m)
    case m
    when NoticeMessage
      if m.public?
        irclog "-=#{m.source}=- #{m.message}", m.target
      else
        irclog "[-=#{m.source}=-] #{m.message}", m.target
      end
    when PrivMessage
      if m.public?
        irclog "<#{m.source}> #{m.message}", m.target
      else
        irclog "[msg(#{m.target})] #{m.message}", m.target
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

  def message(m)
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

  def notice(m)
    if m.private?
      irclog "-#{m.source}- #{m.message}", m.source
    else
      irclog "-#{m.source}- #{m.message}", m.target
    end
  end

  def motd(m)
    m.message.each_line { |line|
      irclog "MOTD: #{line}", "server"
    }
  end

  def nick(m)
    m.is_on.each { |ch|
      irclog "@ #{m.oldnick} is now known as #{m.newnick}", ch
    }
  end

  def quit(m)
    m.was_on.each { |ch|
      irclog "@ Quit: #{m.source}: #{m.message}", ch
    }
  end

  def modechange(m)
    irclog "@ Mode #{m.message} by #{m.source}", m.target
  end

  def join(m)
    if m.address?
      debug "joined channel #{m.channel}"
      irclog "@ Joined channel #{m.channel}", m.channel
    else
      irclog "@ #{m.source} joined channel #{m.channel}", m.channel
    end
  end

  def part(m)
    if(m.address?)
      debug "left channel #{m.channel}"
      irclog "@ Left channel #{m.channel} (#{m.logmessage})", m.channel
    else
      irclog "@ #{m.source} left channel #{m.channel} (#{m.logmessage})", m.channel
    end
  end

  def kick(m)
    if(m.address?)
      debug "kicked from channel #{m.channel}"
      irclog "@ You have been kicked from #{m.channel} by #{m.source} (#{m.logmessage})", m.channel
    else
      irclog "@ #{m.target} has been kicked from #{m.channel} by #{m.source} (#{m.logmessage})", m.channel
    end
  end

  # def invite(m)
  #   # TODO
  # end

  def topic(m)
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
    irclog m.message, ".unknown"
  end
end

ilm = IrcLogModule.new
ilm.priority = -1

