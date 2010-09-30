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
  Config.register Config::ArrayValue.new('markov.readonly',
    :default => [],
    :desc => "Hostmasks and channel names markov should NOT talk to (e.g. idiot*!*@*, #privchan).")
  Config.register Config::IntegerValue.new('markov.max_words',
    :default => 50,
    :validate => Proc.new { |v| (0..100).include? v },
    :desc => "Maximum number of words the bot should put in a sentence")
  Config.register Config::FloatValue.new('markov.learn_delay',
    :default => 0.5,
    :validate => Proc.new { |v| v >= 0 },
    :desc => "Time the learning thread spends sleeping after learning a line. If set to zero, learning from files can be very CPU intensive, but also faster.")
   Config.register Config::IntegerValue.new('markov.delay',
    :default => 5,
    :validate => Proc.new { |v| v >= 0 },
    :desc => "Wait short time before contributing to conversation.")
   Config.register Config::IntegerValue.new('markov.answer_addressed',
    :default => 50,
    :validate => Proc.new { |v| (0..100).include? v },
    :desc => "Probability of answer when addressed by nick")
   Config.register Config::ArrayValue.new('markov.ignore_patterns',
    :default => [],
    :desc => "Ignore these word patterns")

  MARKER = :"\r\n"

  # upgrade a registry entry from 0.9.14 and earlier, converting the Arrays
  # into Hashes of weights
  def upgrade_entry(k, logfile)
    logfile.puts "\t#{k.inspect}"
    logfile.flush
    logfile.fsync

    ar = @registry[k]

    # wipe the current key
    @registry.delete(k)

    # discard empty keys
    if ar.empty?
      logfile.puts "\tEMPTY"
      return
    end

    # otherwise, proceed
    logfile.puts "\t#{ar.inspect}"

    # re-encode key to UTF-8 and cleanup as needed
    words = k.split.map do |w|
      BasicUserMessage.strip_formatting(
        @bot.socket.filter.in(w)
      ).sub(/\001$/,'')
    end

    # old import that failed to split properly?
    if words.length == 1 and words.first.include? '/'
      # split at the last /
      unsplit = words.first
      at = unsplit.rindex('/')
      words = [unsplit[0,at], unsplit[at+1..-1]]
    end

    # if any of the re-split/re-encoded words have spaces,
    # or are empty, we would get a chain we can't convert,
    # so drop it
    if words.first.empty? or words.first.include?(' ') or
      words.last.empty? or words.last.include?(' ')
      logfile.puts "\tSKIPPED"
      return
    end

    # former unclean CTCP, we can't convert this
    if words.first[0] == 1
      logfile.puts "\tSKIPPED"
      return
    end

    # nonword CTCP => SKIP
    # someword CTCP => nonword someword
    if words.last[0] == 1
      if words.first == "nonword"
        logfile.puts "\tSKIPPED"
        return
      end
      words.unshift MARKER
      words.pop
    end

    # intern the old keys
    words.map! do |w|
      ['nonword', MARKER].include?(w) ? MARKER : w.chomp("\001")
    end

    newkey = words.join(' ')
    logfile.puts "\t#{newkey.inspect}"

    # the new key exists already, so we want to merge
    if k != newkey and @registry.key? newkey
      ar2 = @registry[newkey]
      logfile.puts "\tMERGE"
      logfile.puts "\t\t#{ar2.inspect}"
      ar.push(*ar2)
      # and get rid of the key
      @registry.delete(newkey)
    end

    total = 0
    hash = Hash.new(0)

    @chains_mutex.synchronize do
      if @chains.key? newkey
        ar2 = @chains[newkey]
        total += ar2.first
        hash.update ar2.last
      end

      ar.each do |word|
        case word
        when :nonword
          # former marker
          sym = MARKER
        else
          # we convert old words into UTF-8, cleanup, resplit if needed,
          # and only get the first word. we may lose some data for old
          # missplits, but this is the best we can do
          w = BasicUserMessage.strip_formatting(
            @bot.socket.filter.in(word).split.first
          )
          case w
          when /^\001\S+$/, "\001", ""
            # former unclean CTCP or end of CTCP
            next
          else
            # intern after clearing leftover end-of-actions if present
            sym = w.chomp("\001")
          end
        end
        hash[sym] += 1
        total += 1
      end
      if hash.empty?
        logfile.puts "\tSKIPPED"
        return
      end
      logfile.puts "\t#{[total, hash].inspect}"
      @chains[newkey] = [total, hash]
    end
  end

  def upgrade_registry
    # we load all the keys and then iterate over this array because
    # running each() on the registry and updating it at the same time
    # doesn't work
    keys = @registry.keys
    # no registry, nothing to do
    return if keys.empty?

    ki = 0
    log "starting markov database conversion thread (v1 to v2, #{keys.length} keys)"

    keys.each { |k| @upgrade_queue.push k }
    @upgrade_queue.push nil

    @upgrade_thread = Thread.new do
      logfile = File.open(@bot.path('markov-conversion.log'), 'a')
      logfile.puts "=== conversion thread started #{Time.now} ==="
      while k = @upgrade_queue.pop
        ki += 1
        logfile.puts "Key #{ki} (#{@upgrade_queue.length} in queue):"
        begin
          upgrade_entry(k, logfile)
        rescue Exception => e
          logfile.puts "=== ERROR ==="
          logfile.puts e.pretty_inspect
          logfile.puts "=== EREND ==="
        end
        sleep @bot.config['markov.learn_delay'] unless @bot.config['markov.learn_delay'].zero?
      end
      logfile.puts "=== conversion thread stopped #{Time.now} ==="
      logfile.close
    end
    @upgrade_thread.priority = -1
  end

  attr_accessor :chains

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

    @chains = @registry.sub_registry('v2')
    @chains.set_default([])
    @rchains = @registry.sub_registry('v2r')
    @rchains.set_default([])
    @chains_mutex = Mutex.new
    @rchains_mutex = Mutex.new

    @upgrade_queue = Queue.new
    @upgrade_thread = nil
    upgrade_registry

    @learning_queue = Queue.new
    @learning_thread = Thread.new do
      while s = @learning_queue.pop
        learn_line s
        sleep @bot.config['markov.learn_delay'] unless @bot.config['markov.learn_delay'].zero?
      end
    end
    @learning_thread.priority = -1
  end

  def cleanup
    if @upgrade_thread and @upgrade_thread.alive?
      debug 'closing conversion thread'
      @upgrade_queue.clear
      @upgrade_queue.push nil
      @upgrade_thread.join
      debug 'conversion thread closed'
    end

    debug 'closing learning thread'
    @learning_queue.clear
    @learning_queue.push nil
    @learning_thread.join
    debug 'learning thread closed'
    @chains.close
    @rchains.close
    super
  end

  # pick a word from the registry using the pair as key.
  def pick_word(word1, word2=MARKER, chainz=@chains)
    k = "#{word1} #{word2}"
    return MARKER unless chainz.key? k
    wordlist = chainz[k]
    pick_word_from_list wordlist
  end

  # pick a word from weighted hash
  def pick_word_from_list(wordlist)
    total = wordlist.first
    hash = wordlist.last
    return MARKER if total == 0
    return hash.keys.first if hash.length == 1
    hit = rand(total)
    ret = MARKER
    hash.each do |k, w|
      hit -= w
      if hit < 0
        ret = k
        break
      end
    end
    return ret
  end

  def generate_string(word1, word2)
    # limit to max of markov.max_words words
    if word2
      output = [word1, word2]
    else
      output = word1
      keys = []
      @chains.each_key(output) do |key|
        if key.downcase.include? output
          keys << key
        else
          break
        end
      end
      return nil if keys.empty?
      output = keys[rand(keys.size)].split(/ /)
    end
    output = output.split(/ /) unless output.is_a? Array
    input = [word1, word2]
    while output.length < @bot.config['markov.max_words'] and (output.first != MARKER or output.last != MARKER) do
      if output.last != MARKER
        output << pick_word(output[-2], output[-1])
      end
      if output.first != MARKER
        output.insert 0, pick_word(output[0], output[1], @rchains)
      end
    end
    output.delete MARKER
    if output == input
      nil
    else
      output.join(" ")
    end
  end

  def help(plugin, topic="")
    topic, subtopic = topic.split

    case topic
    when "delay"
      "markov delay <value> => Set message delay"
    when "ignore"
      case subtopic
      when "add"
        "markov ignore add <hostmask|channel> => ignore a hostmask or a channel"
      when "list"
        "markov ignore list => show ignored hostmasks and channels"
      when "remove"
        "markov ignore remove <hostmask|channel> => unignore a hostmask or channel"
      else
        "ignore hostmasks or channels -- topics: add, remove, list"
      end
    when "readonly"
      case subtopic
      when "add"
        "markov readonly add <hostmask|channel> => read-only a hostmask or a channel"
      when "list"
        "markov readonly list => show read-only hostmasks and channels"
      when "remove"
        "markov readonly remove <hostmask|channel> => unreadonly a hostmask or channel"
      else
        "restrict hostmasks or channels to read only -- topics: add, remove, list"
      end
    when "status"
      "markov status => show if markov is enabled, probability and amount of messages in queue for learning"
    when "probability"
      "markov probability [<percent>] => set the % chance of rbot responding to input, or display the current probability"
    when "chat"
      case subtopic
      when "about"
        "markov chat about <word> [<another word>] => talk about <word> or riff on a word pair (if possible)"
      else
        "markov chat => try to say something intelligent"
      end
    else
      "markov plugin: listens to chat to build a markov chain, with which it can (perhaps) attempt to (inanely) contribute to 'discussion'. Sort of.. Will get a *lot* better after listening to a lot of chat. Usage: 'chat' to attempt to say something relevant to the last line of chat, if it can -- help topics: ignore, readonly, delay, status, probability, chat, chat about"
    end
  end

  def clean_message(m)
    str = m.plainmessage.dup
    str =~ /^(\S+)([:,;])/
    if $1 and m.target.is_a? Irc::Channel and m.target.user_nicks.include? $1.downcase
      str.gsub!(/^(\S+)([:,;])\s+/, "")
    end
    str.gsub!(/\s{2,}/, ' ') # fix for two or more spaces
    return str.strip
  end

  def probability?
    return @bot.config['markov.probability']
  end

  def status(m,params)
    if @bot.config['markov.enabled']
      reply = _("markov is currently enabled, %{p}% chance of chipping in") % { :p => probability? }
      l = @learning_queue.length
      reply << (_(", %{l} messages in queue") % {:l => l}) if l > 0
      l = @upgrade_queue.length
      reply << (_(", %{l} chains to upgrade") % {:l => l}) if l > 0
    else
      reply = _("markov is currently disabled")
    end
    m.reply reply
  end

  def ignore?(m=nil)
    return false unless m
    return true if m.private?
    return true if m.prefixed?
    @bot.config['markov.ignore'].each do |mask|
      return true if m.channel.downcase == mask.downcase
      return true if m.source.matches?(mask)
    end
    return false
  end

  def readonly?(m=nil)
    return false unless m
    @bot.config['markov.readonly'].each do |mask|
      return true if m.channel.downcase == mask.downcase
      return true if m.source.matches?(mask)
    end
    return false
  end

  def ignore(m, params)
    action = params[:action]
    user = params[:option]
    case action
    when 'remove'
      if @bot.config['markov.ignore'].include? user
        s = @bot.config['markov.ignore']
        s.delete user
        @bot.config['ignore'] = s
        m.reply _("%{u} removed") % { :u => user }
      else
        m.reply _("not found in list")
      end
    when 'add'
      if user
        if @bot.config['markov.ignore'].include?(user)
          m.reply _("%{u} already in list") % { :u => user }
        else
          @bot.config['markov.ignore'] = @bot.config['markov.ignore'].push user
          m.reply _("%{u} added to markov ignore list") % { :u => user }
        end
      else
        m.reply _("give the name of a person or channel to ignore")
      end
    when 'list'
      m.reply _("I'm ignoring %{ignored}") % { :ignored => @bot.config['markov.ignore'].join(", ") }
    else
      m.reply _("have markov ignore the input from a hostmask or a channel. usage: markov ignore add <mask or channel>; markov ignore remove <mask or channel>; markov ignore list")
    end
  end

  def readonly(m, params)
    action = params[:action]
    user = params[:option]
    case action
    when 'remove'
      if @bot.config['markov.readonly'].include? user
        s = @bot.config['markov.readonly']
        s.delete user
        @bot.config['markov.readonly'] = s
        m.reply _("%{u} removed") % { :u => user }
      else
        m.reply _("not found in list")
      end
    when 'add'
      if user
        if @bot.config['markov.readonly'].include?(user)
          m.reply _("%{u} already in list") % { :u => user }
        else
          @bot.config['markov.readonly'] = @bot.config['markov.readonly'].push user
          m.reply _("%{u} added to markov readonly list") % { :u => user }
        end
      else
        m.reply _("give the name of a person or channel to read only")
      end
    when 'list'
      m.reply _("I'm only reading %{readonly}") % { :readonly => @bot.config['markov.readonly'].join(", ") }
    else
      m.reply _("have markov not answer to input from a hostmask or a channel. usage: markov readonly add <mask or channel>; markov readonly remove <mask or channel>; markov readonly list")
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

  def should_talk(m)
    return false unless @bot.config['markov.enabled']
    prob = m.address? ? @bot.config['markov.answer_addressed'] : probability?
    return true if prob > rand(100)
    return false
  end

  # Generates all sequence pairs from array
  # seq_pairs [1,2,3,4] == [ [1,2], [2,3], [3,4]]
  def seq_pairs(arr)
    res = []
    0.upto(arr.size-2) do |i|
      res << [arr[i], arr[i+1]]
    end
    res
  end

  def set_delay(m, params)
    if params[:delay] == "off"
      @bot.config["markov.delay"] = 0
      m.okay
    elsif !params[:delay]
      m.reply _("Message delay is %{delay}" % { :delay => @bot.config["markov.delay"]})
    else
      @bot.config["markov.delay"] = params[:delay].to_i
      m.okay
    end
  end

  def reply_delay(m, line)
    m.replied = true
    if @bot.config['markov.delay'] > 0
      @bot.timer.add_once(1 + rand(@bot.config['markov.delay'])) {
        m.reply line, :nick => false, :to => :public
      }
    else
      m.reply line, :nick => false, :to => :public
    end
  end

  def random_markov(m, message)
    return unless should_talk(m)

    words = clean_message(m).split(/\s+/)
    if words.length < 2
      line = generate_string words.first, nil

      if line and message.index(line) != 0
        reply_delay m, line
        return
      end
    else
      pairs = seq_pairs(words).sort_by { rand }
      pairs.each do |word1, word2|
        line = generate_string(word1, word2)
        if line and message.index(line) != 0
          reply_delay m, line
          return
        end
      end
      words.sort_by { rand }.each do |word|
        line = generate_string word.first, nil
        if line and message.index(line) != 0
          reply_delay m, line
          return
        end
      end
    end
  end

  def chat(m, params)
    line = generate_string(params[:seed1], params[:seed2])
    if line and line != [params[:seed1], params[:seed2]].compact.join(" ")
      m.reply line
    else
      m.reply _("I can't :(")
    end
  end

  def rand_chat(m, params)
    # pick a random pair from the db and go from there
    word1, word2 = MARKER, MARKER
    output = Array.new
    @bot.config['markov.max_words'].times do
      word3 = pick_word(word1, word2)
      break if word3 == MARKER
      output << word3
      word1, word2 = word2, word3
    end
    if output.length > 1
      m.reply output.join(" ")
    else
      m.reply _("I can't :(")
    end
  end

  def learn(*lines)
    lines.each { |l| @learning_queue.push l }
  end

  def unreplied(m)
    return if ignore? m

    # in channel message, the kind we are interested in
    message = m.plainmessage

    if m.action?
      message = "#{m.sourcenick} #{message}"
    end

    random_markov(m, message) unless readonly? m or m.replied?
    learn clean_message(m)
  end


  def learn_triplet(word1, word2, word3)
      k = "#{word1} #{word2}"
      rk = "#{word2} #{word3}"
      @chains_mutex.synchronize do
        total = 0
        hash = Hash.new(0)
        if @chains.key? k
          t2, h2 = @chains[k]
          total += t2
          hash.update h2
        end
        hash[word3] += 1
        total += 1
        @chains[k] = [total, hash]
      end
      @rchains_mutex.synchronize do
        # Reverse
        total = 0
        hash = Hash.new(0)
        if @rchains.key? rk
          t2, h2 = @rchains[rk]
          total += t2
          hash.update h2
        end
        hash[word1] += 1
        total += 1
        @rchains[rk] = [total, hash]
      end
  end


  def learn_line(message)
    # debug "learning #{message.inspect}"
    wordlist = message.strip.split(/\s+/).reject do |w|
      @bot.config['markov.ignore_patterns'].map do |pat|
        w =~ Regexp.new(pat.to_s)
      end.select{|v| v}.size != 0
    end
    return unless wordlist.length >= 2
    word1, word2 = MARKER, MARKER
    wordlist << MARKER
    wordlist.each do |word3|
      learn_triplet(word1, word2, word3.to_sym)
      word1, word2 = word2, word3
    end
  end

  # TODO allow learning from URLs
  def learn_from(m, params)
    begin
      path = params[:file]
      file = File.open(path, "r")
      pattern = params[:pattern].empty? ? nil : Regexp.new(params[:pattern].to_s)
    rescue Errno::ENOENT
      m.reply _("no such file")
      return
    end

    if file.eof?
      m.reply _("the file is empty!")
      return
    end

    if params[:testing]
      lines = []
      range = case params[:lines]
      when /^\d+\.\.\d+$/
        Range.new(*params[:lines].split("..").map { |e| e.to_i })
      when /^\d+$/
        Range.new(1, params[:lines].to_i)
      else
        Range.new(1, [@bot.config['send.max_lines'], 3].max)
      end

      file.each do |line|
        next unless file.lineno >= range.begin
        lines << line.chomp
        break if file.lineno == range.end
      end

      lines = lines.map do |l|
        pattern ? l.scan(pattern).to_s : l
      end.reject { |e| e.empty? }

      if pattern
        unless lines.empty?
          m.reply _("example matches for that pattern at lines %{range} include: %{lines}") % {
            :lines => lines.map { |e| Underline+e+Underline }.join(", "),
            :range => range.to_s
          }
        else
          m.reply _("the pattern doesn't match anything at lines %{range}") % {
            :range => range.to_s
          }
        end
      else
        m.reply _("learning from the file without a pattern would learn, for example: ")
        lines.each { |l| m.reply l }
      end

      return
    end

    if pattern
      file.each { |l| learn(l.scan(pattern).to_s) }
    else
      file.each { |l| learn(l.chomp) }
    end

    m.okay
  end

  def stats(m, params)
    m.reply "Markov status: chains: #{@chains.length} forward, #{@rchains.length} reverse, queued phrases: #{@learning_queue.size}"
  end

end

plugin = MarkovPlugin.new
plugin.map 'markov delay :delay', :action => "set_delay"
plugin.map 'markov delay', :action => "set_delay"
plugin.map 'markov ignore :action :option', :action => "ignore"
plugin.map 'markov ignore :action', :action => "ignore"
plugin.map 'markov ignore', :action => "ignore"
plugin.map 'markov readonly :action :option', :action => "readonly"
plugin.map 'markov readonly :action', :action => "readonly"
plugin.map 'markov readonly', :action => "readonly"
plugin.map 'markov enable', :action => "enable"
plugin.map 'markov disable', :action => "disable"
plugin.map 'markov status', :action => "status"
plugin.map 'markov stats', :action => "stats"
plugin.map 'chat about :seed1 [:seed2]', :action => "chat"
plugin.map 'chat', :action => "rand_chat"
plugin.map 'markov probability [:probability]', :action => "probability",
           :requirements => {:probability => /^\d+%?$/}
plugin.map 'markov learn from :file [:testing [:lines lines]] [using pattern *pattern]', :action => "learn_from", :thread => true,
           :requirements => {
             :testing => /^testing$/,
             :lines   => /^(?:\d+\.\.\d+|\d+)$/ }

plugin.default_auth('ignore', false)
plugin.default_auth('probability', false)
plugin.default_auth('learn', false)

