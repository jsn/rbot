# Author: Giuseppe "Oblomov" Bilotta <giuseppe.bilotta@gmail.com>
# Add a bunch of topic manipulation features

class TopicPlugin < Plugin
  def initialize
    super
    @separator = "|" # default separator
  end

  def help(plugin, topic="")
    case plugin
    when "topic"
      case topic
      when "add"
        return "topic add <text> => add <text> at the end the topic"
      when "prepend"
        return "topic prepend <text> => add <text> at the beginning of the topic"
      when "addat"
        return "topic addat <num> <text> => add <text> at position <num> of the topic"
      when "del"
        return "topic del <num> => remove section <num> from the topic"
      when "separator"
        return "topic sep(arator) [<text>] => get or set the topic section separator"
      when "learn"
        return "topic learn => remembers the topic for later"
      when "restore"
        return "topic restore => resets the topic to the latest remembered one"
      when "set"
        return "topic set <text> => sets the topic to <text>"
      else
        return "topic add(at)|prepend|del|sep(arator)|learn|restore|set: " + \
               "manipulate the topic of the current channel; use topic <#channel> <command> " + \
               "for private addressing"
      end
    end
  end

  def handletopic(m, param)
    return unless m.kind_of?(PrivMessage)
    if m.public?
      ch = m.channel.downcase
    else
      ch = param[:channel].downcase
    end
    cmd = param[:command]
    txt = param[:text].join(" ")
    case cmd
    when /^a(dd|ppend)$/
      topicappend(m, ch, txt)
    when 'prepend'
      topicprepend(m, ch, txt)
    when 'addat'
      if txt =~ /\s*(-?\d+)\s+(.*)\s*/
        num = $1.to_i - 1
        num += 1 if num < 0
        txt = $2
        topicaddat(m, ch, num, txt)
      end
    when /^del(ete)?$/
      if txt =~ /\s*(-?\d+)\s*/
        num=$1.to_i - 1
        num += 1 if num < 0
        topicdel(m, ch, num)
      end
    when 'set'
      topicset(m, ch, txt)
    when /^sep(arator)?$/
      topicsep(m, ch, txt)
    when 'learn'
      learntopic(m, ch)
    when 'restore'
      restoretopic(m, ch)
    else
      m.reply 'unknown command'
    end
  end

  def topicsep(m, ch, txt)
    if txt
      sep = txt.strip
      if sep != ""
        setsep(ch, sep)
      end
    end
    m.reply "Topic separator set to #{getsep(ch)}"
  end

  def setsep(ch, sep)
    if @registry.has_key?(ch)
      data = @registry[ch]
    else
      data = Hash.new
    end
    data[:separator] = sep
    @registry[ch] = data
  end

  def getsep(ch)
    if @registry.has_key?(ch)
      if @registry[ch].has_key?(:separator)
        return @registry[ch][:separator]
      end
    end
    return @separator
  end

  def topicaddat(m, channel, num, txt)
    sep = getsep(channel)
    topic = @bot.channels[channel].topic.to_s
    topicarray = topic.split(/\s+#{Regexp.escape(sep)}\s*/)
    topicarray.insert(num, txt)
    newtopic = topicarray.join(" #{sep} ")
    @bot.topic channel, newtopic
  end

  def topicappend(m, ch, txt)
    topicaddat(m, ch, -1, txt)
  end

  def topicprepend(m, ch, txt)
    topicaddat(m, ch, 0, txt)
  end

  def topicdel(m, channel, num)
    sep = getsep(channel)
    topic = @bot.channels[channel].topic.to_s
    topicarray = topic.split(/\s+#{Regexp.escape(sep)}\s*/)
    topicarray.delete_at(num)
    newtopic = topicarray.join(" #{sep} ")
    @bot.topic channel, newtopic
  end

  def learntopic(m, channel)
    return if !@bot.auth.allow?("learntopic", m.source, m.replyto)
    topic = @bot.channels[channel].topic.to_s
    if @registry.has_key?(channel)
      data = @registry[channel]
    else
      data = Hash.new
    end
    data[:topic] = topic
    @registry[channel] = data
    m.okay
  end

  def restoretopic(m, channel)
    return if !@bot.auth.allow?("restoretopic", m.source, m.replyto)
    if @registry.has_key?(channel) && @registry[channel].has_key?(:topic)
      topic = @registry[channel][:topic]
      @bot.topic channel, topic
    else
      m.reply "I don't remember any topic for this channel"
    end
  end

  def topicset(m, channel, text)
    return if !@bot.auth.allow?("topic", m.source, m.replyto)
    @bot.topic channel, text
  end

end
plugin = TopicPlugin.new
plugin.map 'topic :command *text', :action => 'handletopic', :public => true, :private => false
plugin.map 'topic :channel :command *text', :action => 'handletopic', :public => false, :private => true

