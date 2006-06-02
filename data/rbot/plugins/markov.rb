class MarkovPlugin < Plugin
  def initialize
    super
    @registry.set_default([])
    @registry['enabled'] = false unless @registry.has_key?('enabled')
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
    "markov plugin: listens to chat to build a markov chain, with which it can (perhaps) attempt to (inanely) contribute to 'discussion'. Sort of.. Will get a *lot* better after listening to a lot of chat. usage: 'markov' to attempt to say something relevant to the last line of chat, if it can.  other options to markov: 'ignore' => ignore a hostmask (accept no input), 'status' => show current status, 'probability' => set the % chance of rbot responding to input, 'chat' => try and say something intelligent, 'chat about <foo> <bar>' => riff on a word pair (if possible)"
  end

  def clean_str(s)
    str = s.dup
    str.gsub!(/^\S+[:,;]/, "")
    str.gsub!(/\s{2,}/, ' ') # fix for two or more spaces
    return str.strip
  end

  def probability?
    prob = @registry['probability']
    prob = 25 if prob.kind_of? Array;
    prob = 0 if prob < 0
    prob = 100 if prob > 100
    return prob
  end

  def status(m,params)
    enabled = @registry['enabled']
    if (enabled)
      m.reply "markov is currently enabled, #{probability?}% chance of chipping in"
    else
      m.reply "markov is currently disabled"
    end
  end

  def ignore?(user=nil)
    @registry['ignore_users'].each do |mask|
      return true if Irc.netmaskmatch mask, user
    end
    return false
  end

  def ignore(m, params)
    if @registry['ignore_users'].nil?
      @registry['ignore_users'] = []
    end
    action = params[:action]
    user = params[:option]
    case action
    when 'remove':
      if @registry['ignore_users'].include? user
        s = @registry['ignore_users']
        s.delete user
        @registry['ignore_users'] = s
        m.reply "#{user} removed"
      else
        m.reply "not found in list"
      end
    when 'add':
      if user
        if @registry['ignore_users'].include?(user)
          m.reply "#{user} already in list"
        else
          @registry['ignore_users'] = @registry['ignore_users'].push user 
          m.reply "#{user} added to markov ignore list"
        end
      else
        m.reply "give the name of a person to ignore"
      end
    when 'list':
      m.reply "I'm ignoring #{@registry['ignore_users'].join(", ")}"
    else
      m.reply "have markov ignore the input from a hostmask.  usage: markov ignore add <mask>; markov ignore remove <mask>; markov ignore list"
    end
  end

  def enable(m, params)
    @registry['enabled'] = true
    m.okay
  end

  def probability(m, params)
    @registry['probability'] = params[:probability].to_i
    m.okay
  end

  def disable(m, params)
    @registry['enabled'] = false
    m.okay
  end

  def should_talk
    return false unless @registry['enabled']
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
    @bot.timer.add_once(delay, m) {|m|
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
plugin.map 'markov probability :probability', :action => "probability",
           :requirements => {:probability => /^\d+%?$/}
