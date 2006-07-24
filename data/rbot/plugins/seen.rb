Saw = Struct.new("Saw", :nick, :time, :type, :where, :message)

class SeenPlugin < Plugin
  def help(plugin, topic="")
    "seen <nick> => have you seen, or when did you last see <nick>"
  end
  
  def privmsg(m)
    unless(m.params =~ /^(\S)+$/)
      m.reply "incorrect usage: " + help(m.plugin)
      return
    end

    m.params.gsub!(/\?$/, "")

    if @registry.has_key?(m.params)
      m.reply seen(@registry[m.params])
    else
      m.reply "nope!"
    end
  end

  def listen(m)
    return if m.sourcenick.nil?
    # keep database up to date with who last said what
    if m.kind_of?(PrivMessage)
      return if m.private?
      if m.action?
        @registry[m.sourcenick] = Saw.new(m.sourcenick.dup, Time.new, "ACTION", 
                                          m.target, m.message.dup)
      else
        @registry[m.sourcenick] = Saw.new(m.sourcenick.dup, Time.new, "PUBLIC",
                                          m.target, m.message.dup)
      end
    elsif m.kind_of?(QuitMessage)
      return if m.address?
      @registry[m.sourcenick] = Saw.new(m.sourcenick.dup, Time.new, "QUIT", 
                                        nil, m.message.dup)
    elsif m.kind_of?(NickMessage)
      return if m.address?
      @registry[m.message] = Saw.new(m.sourcenick.dup, Time.new, "NICK", 
                                        nil, m.message.dup)
      @registry[m.sourcenick] = Saw.new(m.sourcenick.dup, Time.new, "NICK", 
                                        nil, m.message.dup)
    elsif m.kind_of?(PartMessage)
      return if m.address?
      @registry[m.sourcenick] = Saw.new(m.sourcenick.dup, Time.new, "PART", 
                                        m.target, m.message.dup)
    elsif m.kind_of?(JoinMessage)
      return if m.address?
      @registry[m.sourcenick] = Saw.new(m.sourcenick.dup, Time.new, "JOIN", 
                                        m.target, m.message.dup)
    elsif m.kind_of?(TopicMessage)
      return if m.address?
      @registry[m.sourcenick] = Saw.new(m.sourcenick.dup, Time.new, "TOPIC", 
                                        m.target, m.message.dup)
    end
  end
  
  def seen(saw)
    ret = "#{saw.nick} was last seen "
    ago = Time.new - saw.time
    
    if (ago.to_i == 0)
      ret += "just now, "
    else
      ret += Utils.secs_to_string(ago) + " ago, "
    end

    case saw.type
    when "PUBLIC"
      ret += "saying #{saw.message}"
    when "ACTION"
      ret += "doing #{saw.nick} #{saw.message}"
    when "NICK"
      ret += "changing nick from #{saw.nick} to #{saw.message}"
    when "PART"
      ret += "leaving #{saw.where}"
    when "JOIN"
      ret += "joining #{saw.where}"
    when "QUIT"
      ret += "quitting IRC (#{saw.message})"
    when "TOPIC"
      ret += "changing the topic of #{saw.where} to #{saw.message}"
    end
  end
  
end
plugin = SeenPlugin.new
plugin.register("seen")
