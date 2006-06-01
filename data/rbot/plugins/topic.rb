# Author: Giuseppe "Oblomov" Bilotta <giuseppe.bilotta@gmail.com>
# Add a bunch of topic manipulation features
# NOTE: topic separator is defined by the global symbol SEPARATOR

SEPARATOR=" | "

class TopicPlugin < Plugin
  def initialize
    super
    @addtopic = /(?:topic(?:append|add)|(?:append|add)topic)/
    @prependtopic = /(?:topicprepend|prependtopic)/
    @addtopicat = /(?:(?:addtopic|topicadd)at)/
    @deltopic = /(?:deltopic|topicdel)/
  end

  def help(plugin, topic="")
    case plugin
    when "topic"
      case topic
      when @addtopic
	return "#{topic} <text> => add <text> at the end the topic"
      when @prependtopic
	return "#{topic} <text> => add <text> at the beginning of the topic"
      when @addtopicat
	return "#{topic} <num> <text> => add <text> at position <num> of the topic"
      when @deltopic
	return "#{topic} <num> => remove section <num> from the topic"
      when "learntopic"
	return "learntopic => remembers the topic for later"
      when "resumetopic"
	return "resumetopic => resets the topic to the latest remembered one"
      when "settopic"
	return "settopic <text> => sets the topic to <text>"
      else
	return "topic commands: addtopic, prependtopic, addtopicat, deltopic, learntopic, resumetopic, settopic"
      end
    when "learntopic"
      return "learntopic => remembers the topic for later"
    when "resumetopic"
      return "resumetopic => resets the topic to the latest remembered one"
    when "settopic"
      return "settopic <text> => sets the topic to <text>"
    end
  end

  def listen(m)
    return unless m.kind_of?(PrivMessage) && m.public?
    command = m.message.dup
    debug command
    if m.address? || command.gsub!(/^!/, "")
      case command
      when /^#{@addtopic}\s+(.*)\s*/
	txt=$1
	debug txt
	if @bot.auth.allow?("topic", m.source, m.replyto)
	  topicappend(m, txt)
	end
      when /^#{@prependtopic}\s+(.*)\s*/
	txt=$1
	debug txt
	if @bot.auth.allow?("topic", m.source, m.replyto)
	  topicaddat(m, 0, txt)
	end
      when /^#{@addtopicat}\s+(-?\d+)\s+(.*)\s*/
	num=$1.to_i - 1
	num += 1 if num < 0
	txt=$2
	debug txt
	if @bot.auth.allow?("topic", m.source, m.replyto)
	  topicaddat(m, num, txt)
	end
      when /^#{@deltopic}\s+(-?\d+)\s*/
	num=$1.to_i - 1
	num += 1 if num < 0
	debug num
	if @bot.auth.allow?("topic", m.source, m.replyto)
	  topicdel(m, num)
	end
      end
    end
  end

  def topicaddat(m, num, txt)
    channel = m.channel.downcase
    topic = @bot.channels[m.channel].topic.to_s
    topicarray = topic.split(SEPARATOR)
    topicarray.insert(num, txt)
    newtopic = topicarray.join(SEPARATOR)
    @bot.topic channel, newtopic
  end

  def topicappend(m, txt)
    channel = m.channel.downcase
    topic = @bot.channels[m.channel].topic.to_s
    topicarray = topic.split(SEPARATOR)
    topicarray << txt
    newtopic = topicarray.join(SEPARATOR)
    @bot.topic channel, newtopic
  end

  def topicdel(m, num)
    channel = m.channel.downcase
    topic = @bot.channels[m.channel].topic.to_s
    topicarray = topic.split(SEPARATOR)
    topicarray.delete_at(num)
    newtopic = topicarray.join(SEPARATOR)
    @bot.topic channel, newtopic
  end

  def learntopic(m, param)
    return if !@bot.auth.allow?("learntopic", m.source, m.replyto)
    channel = m.channel.downcase
    debug channel
    topic = @bot.channels[m.channel].topic.to_s
    @registry[channel] = topic
    @bot.say channel, "Ok"
  end

  def resumetopic(m, param)
    return if !@bot.auth.allow?("resumetopic", m.source, m.replyto)
    channel = m.channel.downcase
    debug "Channel: #{channel}"
    if @registry.has_key?(channel)
      topic = @registry[channel]
      debug "Channel: #{channel}, topic: #{topic}"
      @bot.topic channel, topic
    else
      @bot.say channel, "Non ricordo nulla"
    end
  end

  def settopic(m, param)
    return if !@bot.auth.allow?("topic", m.source, m.replyto)
    channel = m.channel.downcase
    debug "Channel: #{channel}"
    @bot.topic channel, param[:text].to_s
  end

end
plugin = TopicPlugin.new
plugin.register 'topic'
plugin.map 'settopic *text', :action => 'settopic'
plugin.map 'resumetopic'
plugin.map 'learntopic'

