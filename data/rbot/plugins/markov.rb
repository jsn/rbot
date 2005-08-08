class MarkovPlugin < Plugin
  def initialize
    super
    @registry.set_default([])
    @lastline = false
  end

  def markov(m, params)
    # limit to max of 50 words
    return unless @lastline
    word1, word2 = @lastline.split(/\s+/)
    output = word1 + " " + word2
    50.times do
      wordlist = @registry["#{word1}/#{word2}"]
      word3 = wordlist[rand(wordlist.length)]
      break if word3 == :nonword
      output = output + " " + word3
      word1, word2 = word2, word3
    end
    m.reply output
  end
  
  def help(plugin, topic="")
    "markov plugin: listens to chat to build a markov chain, with which it can (perhaps) attempt to (inanely) contribute to 'discussion'. Sort of.. Will get a *lot* better after listening to a lot of chat. usage: 'markov' to attempt to say something relevant to the last line of chat, if it can."
  end
  
  def cleanup(s)
    str = s.dup
    str.gsub!(/^.+:/, "")
    str.gsub!(/^.+,/, "")
    return str.strip
  end

  def listen(m)
    return unless m.kind_of?(PrivMessage) && m.public?
    return if m.address?
    message = cleanup m.message
    # in channel message, the kind we are interested in
    wordlist = message.split(/\s+/)
    return unless wordlist.length > 2
    @lastline = message
    word1, word2 = :nonword, :nonword
    wordlist.each do |word3|
      @registry["#{word1}/#{word2}"] = @registry["#{word1}/#{word2}"].push(word3)
      word1, word2 = word2, word3
    end
    @registry["#{word1}/#{word2}"] = [:nonword]
  end
end
plugin = MarkovPlugin.new
plugin.map 'markov'
