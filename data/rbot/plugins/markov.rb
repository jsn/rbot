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
  Config.register Config::ArrayValue.new('markov.ignore_users',
    :default => [],
    :desc => "Hostmasks of users to be ignored")

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
    @lastline = false
  end

  def generate_string(word1, word2)
    # limit to max of 50 words
    output = word1 + " " + word2

    # try to avoid :nonword in the first iteration
    wordlist = @registry["#{word1} #{word2}"]
    wordlist.delete(:nonword)
    if not wordlist.empty?
      word3 = wordlist[rand(wordlist.length)]
      output = output + " " + word3
      word1, word2 = word2, word3
    end

    49.times do
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

  def ignore?(user=nil)
    return false unless user
    @bot.config['markov.ignore_users'].each do |mask|
      return true if user.matches?(mask)
    end
    return false
  end

  def ignore(m, params)
    action = params[:action]
    user = params[:option]
    case action
    when 'remove':
      if @bot.config['markov.ignore_users'].include? user
        s = @bot.config['markov.ignore_users']
        s.delete user
        @bot.config['ignore_users'] = s
        m.reply "#{user} removed"
      else
        m.reply "not found in list"
      end
    when 'add':
      if user
        if @bot.config['markov.ignore_users'].include?(user)
          m.reply "#{user} already in list"
        else
          @bot.config['markov.ignore_users'] = @bot.config['markov.ignore_users'].push user
          m.reply "#{user} added to markov ignore list"
        end
      else
        m.reply "give the name of a person to ignore"
      end
    when 'list':
      m.reply "I'm ignoring #{@bot.config['markov.ignore_users'].join(", ")}"
    else
      m.reply "have markov ignore the input from a hostmask.  usage: markov ignore add <mask>; markov ignore remove <mask>; markov ignore list"
    end
  end

  def enable(m, params)
    @bot.config['markov.enabled'] = true
    m.okay
  end

  def probability(m, params)
    if params[:probability]
      @bot.config['probability'] = params[:probability].to_i
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
    line = generate_string(word1, word2)
    return unless line
    return if line == message
    @bot.timer.add_once(delay) {
      m.reply line
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
  
  def listen(m)
    return unless m.kind_of?(PrivMessage) && m.public?
    return if m.address?
    return if ignore? m.source

    # in channel message, the kind we are interested in
    message = clean_str m.message

    if m.action?
      message = "#{m.sourcenick} #{message}"
    end
    
    wordlist = message.split(/\s+/)
    return unless wordlist.length >= 2
    @lastline = message
    word1, word2 = :nonword, :nonword
    wordlist.each do |word3|
      @registry["#{word1} #{word2}"] = @registry["#{word1} #{word2}"].push(word3)
      word1, word2 = word2, word3
    end
    @registry["#{word1} #{word2}"] = @registry["#{word1} #{word2}"].push(:nonword)

    return if m.replied?
    random_markov(m, message)
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
