#-- vim:sw=2:et
#++
#
# :title: Hangman Plugin
#
# Author:: Raine Virta <rane@kapsi.fi>
# Copyright:: (C) 2009 Raine Virta
# License:: GPL v2
#
# Description:: Hangman game for rbot
#
# TODO:: scoring and stats
#        some sort of turn-basedness, maybe

module RandomWord
  SITE = "http://coyotecult.com/tools/randomwordgenerator.php"

  def self.get(count=1)
    res = Net::HTTP.post_form(URI.parse(SITE), {'numwords' => count})
    words = res.body.scan(%r{<a.*?\?w=(.*?)\n}).flatten

    count == 1 ? words.first : words
  end
end

class Hangman
  attr_reader :misses, :guesses, :word, :letters

  STAGES = [' (x_x) ', ' (;_;) ', ' (>_<) ', ' (-_-) ', ' (o_~) ', ' (^_^) ', '\(^o^)/']
  HEALTH = STAGES.size-1
  LETTER = /[^\W0-9_]/u

  def initialize(word, channel=nil)
    @word    = word
    @guesses = []
    @misses  = []
    @health  = HEALTH
    @solved  = false
  end

  def letters
    # array of the letters in the word
    @word.split(//u).reject { |c| c !~ LETTER  }.map { |c| c.downcase }
  end

  def face
    STAGES[@health]
  end

  def to_s
    # creates a string that presents the word with unknown letters shown as underscores
    @word.split(//).map { |c|
      @guesses.include?(c.downcase) || c !~ LETTER  ? c : "_"
    }.join
  end

  def guess(str)
    str.downcase!

    # full word guess
    if str !~ /^#{LETTER}$/u
      word.downcase == str ? @solved = true : punish
    else # single letter guess
      return false if @guesses.include?(str) # letter has been guessed before

      unless letters.include?(str)
        @misses << str
        punish
      end

      @guesses << str
    end
  end

  def over?
    won? || lost?
  end

  def won?
    (letters - @guesses).empty? || @solved
  end

  def lost?
    @health.zero?
  end

  def punish
    @health -= 1
  end
end

class HangmanPlugin < Plugin
  def initialize
    super
    @games = {}
    @settings = {}
  end

  def help(plugin, topic="")
    case topic
    when ""
      return "hangman game plugin - topics: play, stop"
    when "play"
      return "hangman play on <channel> with word <word> => use in private chat with the bot to start a game with custom word\n"+
             "hangman play random [with [max|min] length [<|>|== <length>]] => hangman with a random word from #{RandomWord::SITE}\n"+
             "hangman play with wordlist <wordlist> => hangman with random word from <wordlist>"
    when "stop"
      return "hangman stop => quits the current game"
    end
  end

  def get_word(params)
    if params[:word]
      params[:word].join(" ")
    elsif params[:wordlist]
      begin
        wordlist = Wordlist.get(params[:wordlist].join("/"), :spaces => true)
      rescue
        raise "no such wordlist"
      end

      wordlist[rand(wordlist.size)]
    else # getting a random word
      words = RandomWord::get(100)

      if adj = params[:adj]
        words = words.sort_by { |e| e.size }

        if adj == "max"
          words.last
        else
          words.first
        end
      elsif params[:relation] && params[:size]
        words = words.select { |w| w.size.send(params[:relation], params[:size].to_i) }

        unless words.empty?
          words.first
        else
          m.reply "suitable word not found in the set"
          nil
        end
      else
        words.first
      end
    end
  end

  def start(m, params)
    begin
      word = get_word(params) || return
    rescue => e
      m.reply e.message
      return
    end

    if (params[:channel] || m.public?)
      target = if m.public?
        m.channel.to_s
      else
        params[:channel]
      end

      # is the bot on the channel?
      unless @bot.server.channels.names.include?(target.to_s)
        m.reply "i'm not on that channel"
        return
      end

      if @games.has_key?(target)
        m.reply "there's already a hangman game in progress on the channel"
        return
      end

      @bot.say target, "#{m.source} has started a hangman -- join the fun!"
    else
      target = m.source.to_s
    end

    @games[target]    = Hangman.new(word)
    @settings[target] = params

    @bot.say target, game_status(@games[target])
  end

  def stop(m, params)
    source = if m.public?
      m.channel
    else
      m.source
    end

    if @games.has_key?(source.to_s)
      @bot.say source, "oh well, the answer would've been #{Bold}#{@games[source.to_s].word}#{Bold}"
      @games.delete(source.to_s)
    end
  end

  def message(m)
    source = if m.public?
      m.channel.to_s
    else
      m.source.to_s
    end

    if game = @games[source]
      if m.message =~ /^[^\W0-9_]$/u || m.message =~ prepare_guess_regex(game)
        return unless game.guess(m.message)

        m.reply game_status(game)
      end

      if game.over?
        if game.won?
          str = "you nailed it!"
        elsif game.lost?
          str = "you've killed the poor guy :("
        end

        m.reply "#{str} go #{Bold}again#{Bold}?"

        @games.delete(source)
      end
    elsif @settings[source] && m.message =~ /^(?:again|more!?$)/i
      start(m, @settings[source])
    end
  end

  def prepare_guess_regex(game)
    Regexp.new("^#{game.word.split(//).map { |c|
      game.guesses.include?(c) || c !~ Hangman::LETTER ? c : '[^\W0-9_]'
    }.join("")}$")
  end

  def game_status(game)
    "%{word} %{face} %{misses}" % {
      :word   => game.over? ? "#{Bold}#{game.word}#{Bold}" : game.to_s,
      :face   => game.face,
      :misses => game.misses.map { |e| e.upcase }.join(" ")
    }
  end
end

plugin = HangmanPlugin.new
plugin.map "hangman [play] with wordlist *wordlist", :action => 'start'
plugin.map "hangman [play] on :channel with word *word", :action => 'start'
plugin.map "hangman [play] [random] [with [:adj] length [:relation :size]]",
  :action => 'start',
  :requirements => { :adj => /min|max/, :relation => /<|<=|>=|>|==/, :size => /\d+/ }

plugin.map "hangman stop", :action => 'stop'

