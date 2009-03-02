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
# TODO:: some sort of turn-basedness, maybe

module RandomWord
  SITE = "http://coyotecult.com/tools/randomwordgenerator.php"

  def self.get(count=1)
    res = Net::HTTP.post_form(URI.parse(SITE), {'numwords' => count})
    words = res.body.scan(%r{<a.*?\?w=(.*?)\n}).flatten

    count == 1 ? words.first : words
  end
end

module Google
  URL   = "http://www.google.com/wml/search?hl=en&q=define:"
  REGEX = %r{Web definitions for .*?<br/>(.*?)<br/>}

  def self.define(phrase)
    raw = Net::HTTP.get(URI.parse(URL+CGI.escape(phrase)))
    res = raw.scan(REGEX).flatten.map { |e| e.strip }

    res.empty? ? false : res.last
  end
end

class Hangman
  LETTER_VALUE = 5

  module Scoring
    def self.correct_word_guess(game)
      # (2 - (amt of visible chars / word length)) * (amt of chars not visible * 5)
      length    = game.word.size
      visible   = game.visible_characters.size
      invisible = length - visible
      score     = (2-(visible/length.to_f))*(invisible*5)
      score    *= 1.5
      score.round
    end

    def self.incorrect_word_guess(game)
      incorrect_letter(game)
    end

    def self.correct_letter(game)
      ((1/Math.log(game.word.size))+1) * LETTER_VALUE
    end

    def self.incorrect_letter(game)
      Math.log(game.word.size) * -LETTER_VALUE
    end
  end
end

class Hangman
  attr_reader :misses, :guesses, :word, :letters, :scores

  STAGES = [' (x_x) ', ' (;_;) ', ' (>_<) ', ' (-_-) ', ' (o_~) ', ' (^_^) ', '\(^o^)/']
  HEALTH = STAGES.size-1
  LETTER = /[^\W0-9_]/u

  def initialize(word)
    @word     = word
    @guesses  = []
    @misses   = []
    @health   = HEALTH
    @canceled = false
    @solved   = false
    @scores   = {}
  end

  def visible_characters
    # array of visible characters
    characters.reject { |c| !@guesses.include?(c) && c =~ LETTER }
  end

  def letters
    # array of the letters in the word
    characters.reject { |c| c !~ LETTER  }.map { |c| c.downcase }
  end

  def characters
    @word.split(//u)
  end

  def face
    STAGES[@health]
  end

  def to_s
    # creates a string that presents the word with unknown letters shown as underscores
    characters.map { |c|
      @guesses.include?(c.downcase) || c !~ LETTER  ? c : "_"
    }.join
  end

  def guess(player, str)
    @scores[player] ||= 0

    str.downcase!
    # full word guess
    if str !~ /^#{LETTER}$/u
      if word.downcase == str
        @scores[player] += Scoring::correct_word_guess(self)
        @solved = true
      else
        @scores[player] += Scoring::incorrect_word_guess(self)
        punish
      end
    else # single letter guess
      return false if @guesses.include?(str) # letter has been guessed before

      unless letters.include?(str)
        @scores[player] += Scoring::incorrect_letter(self)
        @misses << str
        punish
      else
        @scores[player] += Scoring::correct_letter(self)
      end

      @guesses << str
    end

    return true
  end

  def over?
    won? || lost? || @canceled
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

  def cancel
    @canceled = true
  end
end

class GameManager
  def initialize
    @games = {}
  end

  def current(target)
    game = all(target).last
    game if game && !game.over?
  end

  def all(target)
    @games[target] || @games[target] = []
  end

  def previous(target)
    all(target).select { |game| game.over? }.last
  end

  def new(game)
    all(game.channel) << game
  end
end

define_structure :HangmanPlayerStats, :played, :score
define_structure :HangmanPrivateStats, :played, :score

class StatsHandler
  def initialize(registry)
    @registry = registry
  end

  def save_gamestats(game)
    target = game.channel

    if target.is_a?(User)
      stats = priv_reg[target]
      stats.played += 1
      stats.score  += game.scores.values.last.round
      priv_reg[target] = stats
    elsif target.is_a?(Channel)
      stats = chan_stats(target)
      stats['played'] += 1

      reg = player_stats(target)
      game.scores.each do |user, score|
        pstats = reg[user]
        pstats.played += 1
        pstats.score  += score.round
        reg[user] = pstats
      end
    end
  end

  def player_stats(channel)
    reg = chan_reg(channel).sub_registry('player')
    reg.set_default(HangmanPlayerStats.new(0,0))
    reg
  end

  def chan_stats(channel)
    reg = chan_reg(channel).sub_registry('stats')
    reg.set_default(0)
    reg
  end

  def chan_reg(channel)
    @registry.sub_registry(channel.downcase)
  end

  def priv_reg
    reg = @registry.sub_registry('private')
    reg.set_default(HangmanPrivateStats.new(0,0))
    reg
  end
end

class HangmanPlugin < Plugin
  def initialize
    super
    @games = GameManager.new
    @stats = StatsHandler.new(@registry)
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
    when "define"
      return "define => seeks a definition for the previous answer using google"
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

    if params[:channel] || m.public?
      target = if m.public?
        m.channel
      else
        params[:channel]
      end

      # is the bot on the channel?
      unless @bot.server.channels.names.include?(target.to_s)
        m.reply _("i'm not on that channel")
        return
      end

      if @games.current(target)
        m.reply _("there's already a hangman game in progress on the channel")
        return
      end

      @bot.say target, _("%{nick} has started a hangman -- join the fun!") % {
        :nick => m.source
      }
    else
      target = m.source
    end

    game = Hangman.new(word)

    class << game = Hangman.new(word)
      attr_accessor :channel
    end

    game.channel = target

    @games.new(game)
    @settings[target] = params

    @bot.say target, game_status(@games.current(target))
  end

  def stop(m, params)
    target = m.replyto
    if game = @games.current(target)
      @bot.say target, _("oh well, the answer would've been %{answer}") % {
        :answer => Bold + game.word + Bold
      }

      game.cancel
      @stats.save_gamestats(game)
    else
      @bot.say target, _("no ongoing game")
    end
  end

  def message(m)
    target = m.replyto

    if game = @games.current(target)
      return unless m.message =~ /^[^\W0-9_]$/u || m.message =~ prepare_guess_regex(game)

      if game.guess(m.source, m.message)
        m.reply game_status(game)
      else
        return
      end

      if game.over?
        sentence = if game.won?
          _("you nailed it!")
        elsif game.lost?
          _("you've killed the poor guy :(")
        end

        again = _("go #{Bold}again#{Bold}?")

        scores = []
        game.scores.each do |user, score|
          str = "#{user.nick}: "
          str << if score > 0
            Irc.color(:green)+'+'
          elsif score < 0
            Irc.color(:brown)
          end.to_s

          str << score.round.to_s
          str << Irc.color

          scores << str
        end

        m.reply _("%{sentence} %{again} %{scores}") % {
          :sentence => sentence, :again => again, :scores => scores
        }, :nick => true

        if rand(5).zero?
          m.reply _("wondering what that means? try ´%{prefix}define´") % {
            :prefix => @bot.config['core.address_prefix']
          }
        end

        @stats.save_gamestats(game)
      end
    elsif @settings[target] && m.message =~ /^(?:again|more!?$)/i
      start(m, @settings[target])
    end
  end

  def prepare_guess_regex(game)
    Regexp.new("^#{game.characters.map { |c|
      game.guesses.include?(c) || c !~ Hangman::LETTER ? c : '[^\W0-9_]'
    }.join("")}$")
  end

  def game_status(game)
    str = "%{word} %{face}" % {
      :word   => game.over? ? "#{Bold}#{game.word}#{Bold}" : game.to_s,
      :face   => game.face,
      :misses => game.misses.map { |e| e.upcase }.join(" ")
    }

    str << " %{misses}" % {
      :misses => game.misses.map { |e| e.upcase }.join(" ")
    } unless game.misses.empty?

    str
  end

  def score(m, params)
    target = m.replyto

    unless params[:nick]
      stats = if m.private?
        @stats.priv_reg[target]
      else
        @stats.player_stats(target)[m.source]
      end

      unless stats.played.zero?
        m.reply _("you got %{score} points after %{games} games") % {
          :score => stats.score.round,
          :games => stats.played
        }
      else
        m.reply _("you haven't played hangman, how about playing it right now? :)")
      end
    else
      return unless m.public?

      nick = params[:nick]
      stats = @stats.player_stats(target)[nick]

      unless stats.played.zero?
        m.reply _("%{nick} has %{score} points after %{games} games") % {
          :nick  => nick,
          :score => stats.score.round,
          :games => stats.played
        }
      else
        m.reply _("%{nick} hasn't played hangman :(") % {
          :nick => nick
        }
      end
    end
  end

  def stats(m, params)
    target = m.replyto
    stats  = @stats.chan_stats(target)

    if m.public?
      m.reply _("%{games} games have been played on %{channel}") % {
        :games   => stats['played'],
        :channel => target.to_s
      }
    else
      score(m, params)
    end
  end

  def define(m, params)
    if game = @games.previous(m.replyto)
      return unless res = Google.define(game.word)
      m.reply "#{Bold}#{game.word}#{Bold} -- #{res}"
    end
  end
end

plugin = HangmanPlugin.new
plugin.map "hangman [play] with wordlist *wordlist", :action => 'start'
plugin.map "hangman [play] on :channel with word *word", :action => 'start'
plugin.map "hangman [play] [random] [with [:adj] length [:relation :size]]",
  :action => 'start',
  :requirements => { :adj => /min|max/, :relation => /<|<=|>=|>|==/, :size => /\d+/ }

plugin.map "hangman stop", :action => 'stop'

plugin.map "hangman score [:nick]", :action => 'score'
plugin.map "hangman stats", :action => 'stats'
plugin.map "define", :action => 'define'
