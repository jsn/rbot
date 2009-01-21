#-- vim:sw=2:et
#++
#
# :title: Markov plugin
#
# Author:: Tom Gilbert <tom@linuxbrit.co.uk>
# Copyright:: (C) 2005 Tom Gilbert
#
# Contribute to chat with random phrases built from word sequences learned
# by listening to chat

class MarkovPlugin < Plugin
  Config.register Config::BooleanValue.new('markov.enabled',
    :default => false,
    :desc => "Enable and disable the plugin")
  Config.register Config::IntegerValue.new('markov.probability',
    :default => 25,
    :validate => Proc.new { |v| (0..100).include? v },
    :desc => "Percentage chance of markov plugin chipping in")
  Config.register Config::ArrayValue.new('markov.ignore',
    :default => [],
    :desc => "Hostmasks and channel names markov should NOT learn from (e.g. idiot*!*@*, #privchan).")
  Config.register Config::IntegerValue.new('markov.max_words',
    :default => 50,
    :validate => Proc.new { |v| (0..100).include? v },
    :desc => "Maximum number of words the bot should put in a sentence")

  def initialize
    super
    @registry.set_default([])
    if @registry.has_key?('enabled')
      @bot.config['markov.enabled'] = @registry['enabled']
      @registry.delete('enabled')
    end
    if @registry.has_key?('probability')
      @bot.config['markov.probability'] = @registry['probability']
      @registry.delete('probability')
    end
    if @bot.config['markov.ignore_users']
      debug "moving markov.ignore_users to markov.ignore"
      @bot.config['markov.ignore'] = @bot.config['markov.ignore_users'].dup
      @bot.config.delete('markov.ignore_users'.to_sym)
    end
    @learning_queue = Queue.new
    @learning_thread = Thread.new do
      while s = @learning_queue.pop
        learn s
        sleep 0.5
      end
    end
    @learning_thread.priority = -1
  end

  def cleanup
    debug 'closing learning thread'
    @learning_queue.push nil
    @learning_thread.join
    debug 'learning thread closed'
  end

  def generate_string(word1, word2)
    # limit to max of markov.max_words words
    output = word1 + " " + word2

    # try to avoid :nonword in the first iteration
    wordlist = @registry["#{word1} #{word2}"]
    wordlist.delete(:nonword)
    if not wordlist.empty?
      word3 = wordlist[rand(wordlist.length)]
      output = output + " " + word3
      word1, word2 = word2, word3
    end

    (@bot.config['markov.max_words'] - 1).times do
      wordlist = @registry["#{word1} #{word2}"]
      break if wordlist.empty?
      word3 = wordlist[rand(wordlist.length)]
      break if word3 == :nonword
      output = output + " " + word3
      word1, word2 = word2, word3
    end
    return output
  end

  def help(plugin, topic="")
    "markov plugin: listens to chat to build a markov chain, with which it can (perhaps) attempt to (inanely) contribute to 'discussion'. Sort of.. Will get a *lot* better after listening to a lot of chat. usage: 'markov' to attempt to say something relevant to the last line of chat, if it can.  other options to markov: 'ignore' => ignore a hostmask (accept no input), 'status' => show current status, 'probability [<chance>]' => set the % chance of rbot responding to input, or display the current probability, 'chat' => try and say something intelligent, 'chat about <foo> <bar>' => riff on a word pair (if possible)"
  end

  def clean_str(s)
    str = s.dup
    str.gsub!(/^\S+[:,;]/, "")
    str.gsub!(/\s{2,}/, ' ') # fix for two or more spaces
    return str.strip
  end

  def probability?
    return @bot.config['markov.probability']
  end

  def status(m,params)
    if @bot.config['markov.enabled']
      m.reply "markov is currently enabled, #{probability?}% chance of chipping in"
    else
      m.reply "markov is currently disabled"
    end
  end

  def ignore?(m=nil)
    return false unless m
    return true if m.address? or m.private?
    @bot.config['markov.ignore'].each do |mask|
      return true if m.channel.downcase == mask.downcase
      return true if m.source.matches?(mask)
    end
    return false
  end

  def ignore(m, params)
    action = params[:action]
    user = params[:option]
    case action
    when 'remove':
      if @bot.config['markov.ignore'].include? user
        s = @bot.config['markov.ignore']
        s.delete user
        @bot.config['ignore'] = s
        m.reply "#{user} removed"
      else
        m.reply "not found in list"
      end
    when 'add':
      if user
        if @bot.config['markov.ignore'].include?(user)
          m.reply "#{user} already in list"
        else
          @bot.config['markov.ignore'] = @bot.config['markov.ignore'].push user
          m.reply "#{user} added to markov ignore list"
        end
      else
        m.reply "give the name of a person or channel to ignore"
      end
    when 'list':
      m.reply "I'm ignoring #{@bot.config['markov.ignore'].join(", ")}"
    else
      m.reply "have markov ignore the input from a hostmask or a channel.  usage: markov ignore add <mask or channel>; markov ignore remove <mask or channel>; markov ignore list"
    end
  end

  def enable(m, params)
    @bot.config['markov.enabled'] = true
    m.okay
  end

  def probability(m, params)
    if params[:probability]
      @bot.config['markov.probability'] = params[:probability].to_i
      m.okay
    else
      m.reply _("markov has a %{prob}% chance of chipping in") % { :prob => probability? }
    end
  end

  def disable(m, params)
    @bot.config['markov.enabled'] = false
    m.okay
  end

  def should_talk
    return false unless @bot.config['markov.enabled']
    prob = probability?
    return true if prob > rand(100)
    return false
  end

  def delay
    1 + rand(5)
  end

  def random_markov(m, message)
    return unless should_talk

    word1, word2 = message.split(/\s+/)
    return unless word1 and word2
    line = generate_string(word1, word2)
    return unless line
    # we do nothing if the line we return is just an initial substring
    # of the line we received
    return if message.index(line) == 0
    @bot.timer.add_once(delay) {
      m.reply line, :nick => false
    }
  end

  def chat(m, params)
    line = generate_string(params[:seed1], params[:seed2])
    if line != "#{params[:seed1]} #{params[:seed2]}"
      m.reply line 
    else
      m.reply "I can't :("
    end
  end

  def rand_chat(m, params)
    # pick a random pair from the db and go from there
    word1, word2 = :nonword, :nonword
    output = Array.new
    50.times do
      wordlist = @registry["#{word1} #{word2}"]
      break if wordlist.empty?
      word3 = wordlist[rand(wordlist.length)]
      break if word3 == :nonword
      output << word3
      word1, word2 = word2, word3
    end
    if output.length > 1
      m.reply output.join(" ")
    else
      m.reply "I can't :("
    end
  end
  
  def message(m)
    return if ignore? m

    # in channel message, the kind we are interested in
    message = clean_str m.plainmessage

    if m.action?
      message = "#{m.sourcenick} #{message}"
    end
    
    @learning_queue.push message
    random_markov(m, message) unless m.replied?
  end

  def learn(message)
    # debug "learning #{message}"
    wordlist = message.split(/\s+/)
    return unless wordlist.length >= 2
    word1, word2 = :nonword, :nonword
    wordlist.each do |word3|
      k = "#{word1} #{word2}"
      @registry[k] = @registry[k].push(word3)
      word1, word2 = word2, word3
    end
    k = "#{word1} #{word2}"
    @registry[k] = @registry[k].push(:nonword)
  end
end

plugin = MarkovPlugin.new
plugin.map 'markov ignore :action :option', :action => "ignore"
plugin.map 'markov ignore :action', :action => "ignore"
plugin.map 'markov ignore', :action => "ignore"
plugin.map 'markov enable', :action => "enable"
plugin.map 'markov disable', :action => "disable"
plugin.map 'markov status', :action => "status"
plugin.map 'chat about :seed1 :seed2', :action => "chat"
plugin.map 'chat', :action => "rand_chat"
plugin.map 'markov probability [:probability]', :action => "probability",
           :requirements => {:probability => /^\d+%?$/}
