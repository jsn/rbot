#-- vim:sw=2:et
#++
#
# :title: A-Z Game Plugin for rbot
#
# Author:: Giuseppe "Oblomov" Bilotta <giuseppe.bilotta@gmail.com>
# Author:: Yaohan Chen <yaohan.chen@gmail.com>: Japanese support
#
# Copyright:: (C) 2006 Giuseppe Bilotta
# Copyright:: (C) 2007 GIuseppe Bilotta, Yaohan Chen
#
# License:: GPL v2
#
# A-Z Game: guess the word by reducing the interval of allowed ones
#
# TODO allow manual addition of words

class AzGame

  attr_reader :range, :word
  attr_reader :lang, :rules, :listener
  attr_accessor :tries, :total_tries, :total_failed, :failed, :winner
  def initialize(plugin, lang, rules, word)
    @plugin = plugin
    @lang = lang.to_sym
    @word = word.downcase
    @rules = rules
    @range = [@rules[:first].dup, @rules[:last].dup]
    @listener = @rules[:listener]
    @total_tries = 0
    @total_failed = 0 # not used, reported, updated
    @tries = Hash.new(0)
    @failed = Hash.new(0) # not used, not reported, updated
    @winner = nil
    def @range.to_s
      return "%s -- %s" % self
    end
    if @rules[:list]
      @check = Proc.new { |w| @rules[:list].include?(w) }
    else
      @check_method = "is_#{@lang}?"
      @check = Proc.new { |w| @plugin.send(@check_method, w) }
    end
  end

  def check(word)
    w = word.downcase
    debug "checking #{w} for #{@word} in #{@range}"
    # Since we're called threaded, bail out early if a winner
    # was assigned already
    return [:ignore, nil] if @winner
    return [:bingo, nil] if w == @word
    return [:out, @range] if w < @range.first or w > @range.last
    return [:ignore, @range] if w == @range.first or w == @range.last
    # This is potentially slow (for languages that check online)
    return [:noexist, @range] unless @check.call(w)
    debug "we like it"
    # Check again if there was a winner in the mean time,
    # and bail out if there was
    return [:ignore, nil] if @winner
    if w < @word and w > @range.first
      @range.first.replace(w)
      return [:in, @range]
    elsif w > @word and w < @range.last
      @range.last.replace(w)
      return [:in, @range]
    end
    return [:out, @range]
  end

# TODO scoring: base score is t = ceil(100*exp(-((n-1)^2)/(50^2)))+p for n attempts
#               done by p players; players that didn't win but contributed
#               with a attempts will get t*a/n points

  include Math

  def score
    n = @total_tries
    p = @tries.keys.length
    t = (100*exp(-((n-1)**2)/(50.0**2))).ceil + p
    debug "Total score: #{t}"
    ret = Hash.new
    @tries.each { |k, a|
      ret[k] = [t*a/n, n_("%{count} try", "%{count} tries", a) % {:count => a}]
    }
    if @winner
      debug "replacing winner score of %d with %d" % [ret[@winner].first, t]
      tries = ret[@winner].last
      ret[@winner] = [t, _("winner, %{tries}") % {:tries => tries}]
    end
    return ret.sort_by { |h| h.last.first }.reverse
  end

end

class AzGamePlugin < Plugin

  def initialize
    super
    # if @registry.has_key?(:games)
    #   @games = @registry[:games]
    # else
      @games = Hash.new
    # end
    if @registry.has_key?(:wordcache) and @registry[:wordcache]
      @wordcache = @registry[:wordcache]
    else
      @wordcache = Hash.new
    end
    debug "A-Z wordcache: #{@wordcache.pretty_inspect}"

    @rules = {
      :italian => {
      :good => /s\.f\.|s\.m\.|agg\.|v\.tr\.|v\.(pronom\.)?intr\./, # avv\.|pron\.|cong\.
      :bad => /var\./,
      :first => 'abaco',
      :last => 'zuzzurellone',
      :url => "http://www.demauroparavia.it/%s",
      :wapurl => "http://wap.demauroparavia.it/index.php?lemma=%s",
      :listener => /^[a-z]+$/
    },
    :english => {
      :good => /(?:singular )?noun|verb|adj/,
      :first => 'abacus',
      :last => 'zuni',
      :url => "http://www.chambersharrap.co.uk/chambers/features/chref/chref.py/main?query=%s&title=21st",
      :listener => /^[a-z]+$/
    },
    }

    @wordlist_base = "#{@bot.botclass}/azgame/wordlist-"
  end

  def initialize_wordlist(lang)
    wordlist = @wordlist_base + lang
    if File.exist?(wordlist)
      words = File.readlines(wordlist).map {|line| line.strip}.uniq
      if(words.length >= 4) # something to guess
        rules = {
            :good => /^\S+$/,
            :list => words,
            :first => words[0],
            :last => words[-1],
            :listener => /^\S+$/
        }
        debug "#{lang} wordlist loaded, #{rules[:list].length} lines; first word: #{rules[:first]}, last word: #{rules[:last]}"
        return rules
      end
    end
    return false
  end

  def save
    # @registry[:games] = @games
    @registry[:wordcache] = @wordcache
  end

  def message(m)
    return if m.channel.nil? or m.address?
    k = m.channel.downcase.to_s # to_sym?
    return unless @games.key?(k)
    return if m.params
    word = m.plugin.downcase
    return unless word =~ @games[k].listener
    word_check(m, k, word)
  end

  def word_check(m, k, word)
    # Not really safe ... what happens
    Thread.new {
      isit = @games[k].check(word)
      case isit.first
      when :bingo
        m.reply _("%{bold}BINGO!%{bold} the word was %{underline}%{word}%{underline}. Congrats, %{bold}%{player}%{bold}!") % {:bold => Bold, :underline => Underline, :word => word, :player => m.sourcenick}
        @games[k].total_tries += 1
        @games[k].tries[m.source] += 1
        @games[k].winner = m.source
        ar = @games[k].score.inject([]) { |res, kv|
          res.push("%s: %d (%s)" % kv.flatten)
        }
        m.reply _("The game was won after %{tries} tries. Scores for this game:    %{scores}") % {:tries => @games[k].total_tries, :scores => ar.join('; ')}
        @games.delete(k)
      when :out
        m.reply _("%{word} is not in the range %{bold}%{range}%{bold}") % {:word => word, :bold => Bold, :range => isit.last} if m.address?
      when :noexist
        # bail out early if the game was won in the mean time
        return if !@games[k] or @games[k].winner
        m.reply _("%{word} doesn't exist or is not acceptable for the game") % {:word => word}
        @games[k].total_failed += 1
        @games[k].failed[m.source] += 1
      when :in
        # bail out early if the game was won in the mean time
        return if !@games[k] or @games[k].winner
        m.reply _("close, but no cigar. New range: %{bold}%{range}%{bold}") % {:bold => Bold, :range => isit.last}
        @games[k].total_tries += 1
        @games[k].tries[m.source] += 1
      when :ignore
        m.reply _("%{word} is already one of the range extrema: %{range}") % {:word => word, :range => isit.last} if m.address?
      else
        m.reply _("hm, something went wrong while verifying %{word}")
      end
    }
  end

  def manual_word_check(m, params)
    k = m.channel.downcase.to_s
    word = params[:word].downcase
    if not @games.key?(k)
      m.reply _("no A-Z game running here, can't check if %{word} is valid, can I?")
      return
    end
    if word !~ /^\S+$/
      m.reply _("I only accept single words composed by letters only, sorry")
      return
    end
    word_check(m, k, word)
  end

  def stop_game(m, params)
    return if m.channel.nil? # Shouldn't happen, but you never know
    k = m.channel.downcase.to_s # to_sym?
    if @games.key?(k)
      m.reply _("the word in %{bold}%{range}%{bold} was:   %{bold}%{word}%{bold}") % {:bold => Bold, :range => @games[k].range, :word => @games[k].word}
      ar = @games[k].score.inject([]) { |res, kv|
        res.push("%s: %d (%s)" % kv.flatten)
      }
      m.reply _("The game was cancelled after %{tries} tries. Scores for this game would have been:    %{scores}") % {:tries => @games[k].total_tries, :scores => ar.join('; ')}
      @games.delete(k)
    else
      m.reply _("no A-Z game running in this channel ...")
    end
  end

  def start_game(m, params)
    return if m.channel.nil? # Shouldn't happen, but you never know
    k = m.channel.downcase.to_s # to_sym?
    unless @games.key?(k)
      lang = (params[:lang] || @bot.config['core.language']).to_sym
      method = 'random_pick_'+lang.to_s
      m.reply _("let me think ...")
      if @rules.has_key?(lang) and self.respond_to?(method)
        word = self.send(method)
        if word.empty?
          m.reply _("couldn't think of anything ...")
          return
        end
        m.reply _("got it!")
        @games[k] = AzGame.new(self, lang, @rules[lang], word)
      elsif !@rules.has_key?(lang) and rules = initialize_wordlist(lang)
        word = random_pick_wordlist(rules)
        if word.empty?
          m.reply _("couldn't think of anything ...")
          return
        end
        m.reply _("got it!")
        @games[k] = AzGame.new(self, lang, rules, word)
      else
        m.reply _("I can't play A-Z in %{lang}, sorry") % {:lang => lang}
        return
      end
    end
    tr = @games[k].total_tries
    # this message building code is rewritten to make translation easier
    if tr == 0
      tr_msg = ''
    else
      f_tr = @games[k].total_failed
      if f_tr > 0
        tr_msg = _(" (after %{total_tries} and %{invalid_tries})") %
           { :total_tries => n_("%{count} try", "%{count} tries", tr) %
                             {:count => tr},
             :invalid_tries => n_("%{count} invalid try", "%{count} invalid tries", tr) %
                               {:count => f_tr} }
      else
        tr_msg = _(" (after %{total_tries})") %
                 { :total_tries => n_("%{count} try", "%{count} tries", tr) %
                             {:count => tr}}
      end
    end

    m.reply _("A-Z: %{bold}%{range}%{bold}") % {:bold => Bold, :range => @games[k].range} + tr_msg
    return
  end

  def wordlist(m, params)
    pars = params[:params]
    lang = (params[:lang] || @bot.config['core.language']).to_sym
    wc = @wordcache[lang] || Hash.new rescue Hash.new
    cmd = params[:cmd].to_sym rescue :count
    case cmd
    when :count
      m.reply n_("I have %{count} %{lang} word in my cache", "I have %{count} %{lang} words in my cache", wc.size) % {:count => wc.size, :lang => lang}
    when :show, :list
      if pars.empty?
        m.reply _("provide a regexp to match")
        return
      end
      begin
        regex = /#{pars[0]}/
        matches = wc.keys.map { |k|
          k.to_s
        }.grep(regex)
      rescue
        matches = []
      end
      if matches.size == 0
        m.reply _("no %{lang} word I know match %{pattern}") % {:lang => lang, :pattern => pars[0]}
      elsif matches.size > 25
        m.reply _("more than 25 %{lang} words I know match %{pattern}, try a stricter matching") % {:lang => lang, :pattern => pars[0]}
      else
        m.reply "#{matches.join(', ')}"
      end
    when :info
      if pars.empty?
        m.reply _("provide a word")
        return
      end
      word = pars[0].downcase.to_sym
      if not wc.key?(word)
        m.reply _("I don't know any %{lang} word %{word}") % {:lang => lang, :word => word}
        return
      end
      if wc[word].key?(:when)
        tr = _("%{word} learned from %{user} on %{date}") % {:word => word, :user => wc[word][:who], :date => wc[word][:when]}
      else
        tr = _("%{word} learned from %{user}") % {:word => word, :user => wc[word][:who]} 
      end
      m.reply tr
    when :delete 
      if pars.empty?
        m.reply _("provide a word")
        return
      end
      word = pars[0].downcase.to_sym
      if not wc.key?(word)
        m.reply _("I don't know any %{lang} word %{word}") % {:lang => lang, :word => word}
        return
      end
      wc.delete(word)
      @bot.okay m.replyto
    when :add
      if pars.empty?
        m.reply _("provide a word")
        return
      end
      word = pars[0].downcase.to_sym
      if wc.key?(word)
        m.reply _("I already know the %{lang} word %{word}")
        return
      end
      wc[word] = { :who => m.sourcenick, :when => Time.now }
      @bot.okay m.replyto
    else
    end
  end

  # return integer between min and max, inclusive
  def rand_between(min, max)
    rand(max - min + 1) + min
  end

  def random_pick_wordlist(rules, min=nil, max=nil)
    min = rules[:first] if min.nil_or_empty?
    max = rules[:last]  if max.nil_or_empty?
    debug "Randomly picking word between #{min} and #{max}"
    min_index = rules[:list].index(min)
    max_index = rules[:list].index(max)
    debug "Index between #{min_index} and #{max_index}"
    index = rand_between(min_index + 1, max_index - 1)
    debug "Index generated: #{index}"
    word = rules[:list][index]
    debug "Randomly picked #{word}"
    word
  end

  def is_italian?(word)
    unless @wordcache.key?(:italian)
      @wordcache[:italian] = Hash.new
    end
    wc = @wordcache[:italian]
    return true if wc.key?(word.to_sym)
    rules = @rules[:italian]
    p = @bot.httputil.get(rules[:wapurl] % word, :open_timeout => 60, :read_timeout => 60)
    if not p
      error "could not connect!"
      return false
    end
    debug p
    p.scan(/<anchor>#{word} - (.*?)<go href="lemma.php\?ID=([^"]*?)"/) { |qual, url|
      debug "new word #{word} of type #{qual}"
      if qual =~ rules[:good] and qual !~ rules[:bad]
        wc[word.to_sym] = {:who => :dict}
        return true
      end
      next
    }
    return false
  end

  def random_pick_italian(min=nil,max=nil)
    # Try to pick a random word between min and max
    word = String.new
    min = min.to_s
    max = max.to_s
    if min > max
      m.reply "#{min} > #{max}"
      return word
    end
    rules = @rules[:italian]
    min = rules[:first] if min.empty?
    max = rules[:last]  if max.empty?
    debug "looking for word between #{min.inspect} and #{max.inspect}"
    return word if min.empty? or max.empty?
    begin
      while (word <= min or word >= max or word !~ /^[a-z]+$/)
        debug "looking for word between #{min} and #{max} (prev: #{word.inspect})"
        # TODO for the time being, skip words with extended characters
        unless @wordcache.key?(:italian)
          @wordcache[:italian] = Hash.new
        end
        wc = @wordcache[:italian]

        if wc.size > 0
          cache_or_url = rand(2)
          if cache_or_url == 0
            debug "getting word from wordcache"
            word = wc.keys[rand(wc.size)].to_s
            next
          end
        end

        # TODO when doing ranges, adapt this choice
        l = ('a'..'z').to_a[rand(26)]
        debug "getting random word from dictionary, starting with letter #{l}"
        first = rules[:url] % "lettera_#{l}_0_50"
        p = @bot.httputil.get(first)
        max_page = p.match(/ \/ (\d+)<\/label>/)[1].to_i
        pp = rand(max_page)+1
        debug "getting random word from dictionary, starting with letter #{l}, page #{pp}"
        p = @bot.httputil.get(first+"&pagina=#{pp}") if pp > 1
        lemmi = Array.new
        good = rules[:good]
        bad =  rules[:bad]
        # We look for a lemma composed by a single word and of length at least two
        p.scan(/<li><a href="([^"]+?)" title="consulta il lemma ([^ "][^ "]+?)">.*?&nbsp;(.+?)<\/li>/) { |url, prelemma, tipo|
          lemma = prelemma.downcase.to_sym
          debug "checking lemma #{lemma} (#{prelemma}) of type #{tipo} from url #{url}"
          next if wc.key?(lemma)
          case tipo
          when good
            if tipo =~ bad
              debug "refusing, #{bad}"
              next
            end
            debug "good one"
            lemmi << lemma
            wc[lemma] = {:who => :dict}
          else
            debug "refusing, not #{good}"
          end
        }
        word = lemmi[rand(lemmi.length)].to_s
      end
    rescue => e
      error "error #{e.inspect} while looking up a word"
      error e.backtrace.join("\n")
    end
    return word
  end

  def is_english?(word)
    unless @wordcache.key?(:english)
      @wordcache[:english] = Hash.new
    end
    wc = @wordcache[:english]
    return true if wc.key?(word.to_sym)
    rules = @rules[:english]
    p = @bot.httputil.get(rules[:url] % CGI.escape(word))
    if not p
      error "could not connect!"
      return false
    end
    debug p
    if p =~ /<span class="(?:hwd|srch)">#{word}<\/span>([^\n]+?)<span class="psa">#{rules[:good]}<\/span>/i
      debug "new word #{word}"
        wc[word.to_sym] = {:who => :dict}
        return true
    end
    return false
  end

  def random_pick_english(min=nil,max=nil)
    # Try to pick a random word between min and max
    word = String.new
    min = min.to_s
    max = max.to_s
    if min > max
      m.reply "#{min} > #{max}"
      return word
    end
    rules = @rules[:english]
    min = rules[:first] if min.empty?
    max = rules[:last]  if max.empty?
    debug "looking for word between #{min.inspect} and #{max.inspect}"
    return word if min.empty? or max.empty?
    begin
      while (word <= min or word >= max or word !~ /^[a-z]+$/)
        debug "looking for word between #{min} and #{max} (prev: #{word.inspect})"
        # TODO for the time being, skip words with extended characters
        unless @wordcache.key?(:english)
          @wordcache[:english] = Hash.new
        end
        wc = @wordcache[:english]

        if wc.size > 0
          cache_or_url = rand(2)
          if cache_or_url == 0
            debug "getting word from wordcache"
            word = wc.keys[rand(wc.size)].to_s
            next
          end
        end

        # TODO when doing ranges, adapt this choice
        l = ('a'..'z').to_a[rand(26)]
        ll = ('a'..'z').to_a[rand(26)]
        random = [l,ll].join('*') + '*'
        debug "getting random word from dictionary, matching #{random}"
        p = @bot.httputil.get(rules[:url] % CGI.escape(random))
        debug p
        lemmi = Array.new
        good = rules[:good]
        # We look for a lemma composed by a single word and of length at least two
        p.scan(/<span class="(?:hwd|srch)">(.*?)<\/span>([^\n]+?)<span class="psa">#{rules[:good]}<\/span>/i) { |prelemma, discard|
          lemma = prelemma.downcase
          debug "checking lemma #{lemma} (#{prelemma}) and discarding #{discard}"
          next if wc.key?(lemma.to_sym)
          if lemma =~ /^[a-z]+$/
            debug "good one"
            lemmi << lemma
            wc[lemma.to_sym] = {:who => :dict}
          else
            debug "funky characters, not good"
          end
        }
        next if lemmi.empty?
        word = lemmi[rand(lemmi.length)]
      end
    rescue => e
      error "error #{e.inspect} while looking up a word"
      error e.backtrace.join("\n")
    end
    return word
  end

  def help(plugin, topic="")
    case topic
    when 'manage'
      return _("az [lang] word [count|list|add|delete] => manage the az wordlist for language lang (defaults to current bot language)")
    when 'cancel'
      return _("az cancel => abort current game")
    when 'check'
      return _('az check <word> => checks <word> against current game')
    when 'rules'
      return _("try to guess the word the bot is thinking of; if you guess wrong, the bot will use the new word to restrict the range of allowed words: eventually, the range will be so small around the correct word that you can't miss it")
    when 'play'
      return _("az => start a game if none is running, show the current word range otherwise; you can say 'az <language>' if you want to play in a language different from the current bot default")
    end
    offset = @wordlist_base.length
    langs = @rules.keys
    wls = Dir.glob(@wordlist_base + "*").map { |f| f[offset,f.length].intern rescue nil }.compact - langs
    return [
      _("az topics: play, rules, cancel, manage, check"),
      _("available languages: %{langs}") % { :langs => langs.join(", ") },
      wls.empty? ? nil : _("available wordlists: %{wls}") % { :wls => wls.join(", ") },
    ].compact.join(". ")

  end

end

plugin = AzGamePlugin.new
plugin.map 'az [:lang] word :cmd *params', :action=>'wordlist', :defaults => { :lang => nil, :cmd => 'count', :params => [] }, :auth_path => '!az::edit!'
plugin.map 'az cancel', :action=>'stop_game', :private => false
plugin.map 'az check :word', :action => 'manual_word_check', :private => false
plugin.map 'az [play] [:lang]', :action=>'start_game', :private => false, :defaults => { :lang => nil }

