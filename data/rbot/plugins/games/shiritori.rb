#-- vim:sw=2:et
#kate: indent-width 2
#++
# 
# :title: Shiritori Plugin for RBot
#
# Author:: Yaohan Chen <yaohan.chen@gmail.com>
# Copyright:: (c) 2007 Yaohan Chen
# License:: GNU Public License
#
#
# Shiritori is a word game where a few people take turns to continue a chain of words.
# To continue a word, the next word must start with the ending of the previous word,
# usually defined as the one to few letters/characters at the end. This plugin allows
# playing several games, each per channel. A game can be turn-based, where only new
# players can interrupt a turn to join, or a free mode where anyone can speak at any
# time.
# 
# TODO
# * a system to describe settings, so they can be displayed, changed and saved
# * adjust settings during game
# * allow other definitions of continues?
# * read default settings from configuration
# * keep statistics
# * other forms of dictionaries


# Abstract class representing a dictionary used by Shiritori
class Dictionary
  # whether string s is a word
  def has_word?(s)
    raise NotImplementedError
  end
  
  # whether any word starts with prefix, excluding words in excludes. This can be
  # possible with non-enumerable dictionaries since some dictionary engines provide
  # prefix searching.
  def any_word_starting?(prefix, excludes)
    raise NotImplementedError
  end
end

# A Dictionary that uses a enumrable word list.
class WordlistDictionary < Dictionary
  def initialize(words)
    super()
    @words = words
    debug "Created dictionary with #{@words.length} words"
  end
  
    # whether string s is a word
  def has_word?(s)
    @words.include? s
  end
  
  # whether any word starts with prefix, excluding words in excludes
  def any_word_starting?(prefix, excludes)
    # (@words - except).any? {|w| w =~ /\A#{prefix}.+/}
    # this seems to be faster:
    !(@words.grep(/\A#{prefix}.+/) - excludes).empty?
  end
end

# Logic of shiritori game, deals with checking whether words continue the chain, and
# whether it's possible to continue a word
class Shiritori
  attr_reader :used_words
  
  # dictionary:: a Dictionary object
  # overlap_lengths:: a Range for allowed lengths to overlap when continuing words
  # check_continuable:: whether all words are checked whether they're continuable,
  #                     before being commited
  # allow_reuse:: whether words are allowed to be used again
  def initialize(dictionary, overlap_lengths, check_continuable, allow_reuse)
    @dictionary = dictionary
    @overlap_lengths = overlap_lengths
    @check_continuable = check_continuable
    @allow_reuse = allow_reuse
    @used_words = []
  end
  
  # Prefix of s with length n
  def head_of(s, n)
    # TODO ruby2 unicode
    s.split(//u)[0, n].join
  end
  # Suffix of s with length n
  def tail_of(s, n)
    # TODO ruby2 unicode
    s.split(//u)[-n, n].join
  end
  # Number of unicode characters in string
  def len(s)
    # TODO ruby2 unicode
    s.split(//u).length
  end
  # return subrange of range r that's under n
  def range_under(r, n)
    r.begin .. [r.end, n-1].min
  end
  
  # TODO allow the ruleset to customize this
  def continues?(w2, w1)
    # this uses the definition w1[-n,n] == w2[0,n] && n < [w1.length, w2.length].min
    # TODO it might be worth allowing <= for the second clause
    range_under(@overlap_lengths, [len(w1), len(w2)].min).any? {|n|
      tail_of(w1, n)== head_of(w2, n)}
  end
  
  # Checks whether *any* unused word in the dictionary completes the word
  # This has the limitation that it can't detect when a word is continuable, but the
  # only continuers aren't continuable
  def continuable_from?(s)
    range_under(@overlap_lengths, len(s)).any? {|n|
      @dictionary.any_word_starting?(tail_of(s, n), @used_words) }
  end
  
  # Given a string, give a verdict based on current shiritori state and dictionary 
  def process(s)
    # TODO optionally allow used words
    # TODO ruby2 unicode
    if len(s) < @overlap_lengths.min || !@dictionary.has_word?(s)
      debug "#{s} is too short or not in dictionary"
      :ignore
    elsif @used_words.empty?
      if !@check_continuable || continuable_from?(s)
        @used_words << s
        :start
      else
        :start_end
      end
    elsif continues?(s, @used_words.last)
      if !@allow_reuse && @used_words.include?(s)
        :used
      elsif !@check_continuable || continuable_from?(s)
        @used_words << s
        :next
      else
        :end
      end
    else
      :ignore
    end
  end
end

# A shiritori game on a channel. keeps track of rules related to timing and turns,
# and interacts with players
class ShiritoriGame
  # timer:: the bot.timer object
  # say:: a Proc which says the given message on the channel
  # when_die:: a Proc that removes the game from plugin's list of games
  def initialize(channel, ruleset, timer, say, when_die)
    raise ArgumentError unless [:words, :overlap_lengths, :check_continuable,
         :end_when_uncontinuable, :allow_reuse, :listen, :normalize, :time_limit,
         :lose_when_timeout].all? {|r| ruleset.has_key?(r)}
    @last_word = nil
    @players = []
    @booted_players = []
    @ruleset = ruleset
    @channel = channel
    @timer = timer
    @timer_handle = nil
    @say = say
    @when_die = when_die
    
    # TODO allow other forms of dictionaries
    dictionary = WordlistDictionary.new(@ruleset[:words])
    @game = Shiritori.new(dictionary, @ruleset[:overlap_lengths],
                                      @ruleset[:check_continuable],
                                      @ruleset[:allow_reuse])
  end
  
  # Whether the players must take turns
  # * when there is only one player, turns are not enforced
  # * when time_limit > 0, new players can join at any time, but existing players must
  #   take turns, each of which expires after time_limit
  # * when time_imit is 0, anyone can speak in the game at any time
  def take_turns? 
    @players.length > 1 && @ruleset[:time_limit] > 0
  end
  
  # the player who has the current turn
  def current_player
    @players.first
  end
  # the word to continue in the current turn
  def current_word
    @game.used_words[-1]
  end
  # the word in the chain before current_word
  def previous_word
    @game.used_words[-2]
  end
  
  # announce the current word, and player if take_turns?
  def announce
    if take_turns?
      @say.call "#{current_player}, it's your turn. #{previous_word} -> #{current_word}"
    elsif @players.empty?
      @say.call "No one has given the first word yet. Say the first word to start."
    else
      @say.call "Poor #{current_player} is playing alone! Anyone care to join? #{previous_word} -> #{current_word}"
    end
  end
  # create/reschedule timer
  def restart_timer
    # the first time the method is called, a new timer is added
    @timer_handle = @timer.add(@ruleset[:time_limit]) {time_out}
    # afterwards, it will reschdule the timer
    instance_eval do
      def restart_timer
        @timer.reschedule(@timer_handle, @ruleset[:time_limit])
      end
    end
  end
  # switch to the next player's turn if take_turns?, and announce current words
  def next_player
    # when there's only one player, turns and timer are meaningless
    if take_turns?
      # place the current player to the last position, to implement circular queue
      @players << @players.shift
      # stop previous timer and set time for this turn
      restart_timer
    end
    announce
  end
  
  # handle when turn time limit goes out
  def time_out
    if @ruleset[:lose_when_timeout]
      @say.call "#{current_player} took too long and is out of the game. Try again next game!"
      if @players.length == 2 
        # 2 players before, and one should remain now
        # since the game is ending, save the trouble of removing and booting the player
        @say.call "#{@players[1]} is the last remaining player and the winner! Congratulations!"
        die
      else
        @booted_players << @players.shift
        announce
      end
    else
      @say.call "#{current_player} took too long and skipped the turn."
      next_player
    end
  end

  # change the rules, and update state when necessary
  def change_rules(rules)
    @ruleset.update! rules
  end

  # handle a message to @channel
  def handle_message(m)
    message = m.message
    speaker = m.sourcenick.to_s
    
    return unless @ruleset[:listen] =~ message

    # in take_turns mode, only new players are allowed to interrupt a turn
    return if @booted_players.include? speaker ||
              (take_turns? && 
               speaker != current_player &&
               (@players.length > 1 && @players.include?(speaker)))

    # let Shiritori process the message, and act according to result
    case @game.process @ruleset[:normalize].call(message)
    when :start
      @players << speaker
      m.reply "#{speaker} has given the first word: #{current_word}"
    when :next
      if !@players.include?(speaker)
        # A new player
        @players.unshift speaker
        m.reply "Welcome to shiritori, #{speaker}."
      end
      next_player
    when :used
      m.reply "The word #{message} has been used. Retry from #{current_word}"
    when :end
      # TODO respect shiritori.end_when_uncontinuable setting
      if @ruleset[:end_when_uncontinuable]
        m.reply "It's impossible to continue the chain from #{message}. The game has ended. Thanks a lot, #{speaker}! :("
        die
      else
        m.reply "It's impossible to continue the chain from #{message}. Retry from #{current_word}"
      end
    when :start_end
      # when the first word is uncontinuable, the game doesn't stop, as presumably
      # someone wanted to play
      m.reply "It's impossible to continue the chain from #{message}. Start with another word."
    end
  end
  
  # end the game
  def die
    # redefine restart_timer to no-op
    instance_eval do
      def restart_timer
      end
    end
    # remove any registered timer
    @timer.remove @timer_handle unless @timer_handle.nil?
    # should remove the game object from plugin's @games list
    @when_die.call
  end
end

# shiritori plugin for rbot
class ShiritoriPlugin < Plugin
  def help(plugin, topic="")
    "A game in which each player must continue the previous player's word, by using its last one or few characters/letters of the word to start a new word. 'shiritori <ruleset>' => Play shiritori with a set of rules. Available rulesets: #{@rulesets.keys.join ', '}. 'shiritori stop' => Stop the current shiritori game."
  end
  
  def initialize()
    super
    @games = {}
    
    # TODO make rulesets more easily customizable
    # TODO initialize default ruleset from config
    # Default values of rulesets
    @default_ruleset = {
      # the range of the length of "tail" that must be followed to continue the chain
      :overlap_lengths => 1..2,
      # messages cared about, pre-normalize
      :listen => /\A\S+\Z/u,
      # normalize messages with this function before checking with Shiritori
      :normalize => lambda {|w| w},
      # number of seconds for each player's turn
      :time_limit => 60,
      # when the time limit is reached, the player's booted out of the game and cannot
      # join until the next game
      :lose_when_timeout => true,
      # check whether the word is continuable before adding it into chain
      :check_continuable => true,
      # allow reusing used words
      :allow_reuse => false,
      # end the game when an uncontinuable word is said
      :end_when_uncontinuable => true
    }
    @rulesets = {
      'english' => {
        :wordlist_file => 'english',
        :listen => /\A[a-zA-Z]+\Z/,
        :overlap_lengths => 2..5,
        :normalize => lambda {|w| w.downcase},
        :desc => 'Use English words; case insensitive; 2-6 letters at the beginning of the next word must overlap with those at the end of the previous word.'
      },
      'japanese' => {
        :wordlist_file => 'japanese',
        :listen => /\A\S+\Z/u,
        :overlap_lengths => 1..4,
        :desc => 'Use Japanese words in hiragana; 1-4 kana at the beginning of the next word must overlap with those at the end of the previous word.',
        # Optionally use a module to normalize Japanese words, enabling input in multiple writing systems
      }
    }
    @rulesets.each_value do |ruleset|
      # set default values for each rule to default_ruleset's values
      ruleset.replace @default_ruleset.merge(ruleset)
      unless ruleset.has_key?(:words)
        if ruleset.has_key?(:wordlist_file)
          # TODO read words only when rule is used
          # read words separated by newlines from file
          ruleset[:words] =
            File.new("#{@bot.botclass}/shiritori/#{ruleset[:wordlist_file]}").grep(
              ruleset[:listen]) {|l| ruleset[:normalize].call l.chomp}
        else
          raise NotImplementedError
        end
      end
    end
  end
  
  # start shiritori in a channel
  def cmd_shiritori(m, params)
    if @games.has_key?( m.channel )
      m.reply "Already playing shiritori here"
      @games[m.channel].announce
    else
      if @rulesets.has_key? params[:ruleset]
        @games[m.channel] = ShiritoriGame.new(
          m.channel, @rulesets[params[:ruleset]],
          @bot.timer,
          lambda {|msg| m.reply msg},
          lambda {remove_game m.channel} )
        m.reply "Shiritori has started. Please say the first word"
      else
        m.reply "There is no defined ruleset named #{params[:ruleset]}"
      end
    end
  end
  
  # change rules for current game
  def cmd_set(m, params)
    require 'enumerator'
    new_rules = {}
    params[:rules].each_slice(2) {|opt, value| new_rules[opt] = value}
    raise NotImplementedError
  end
  
  # stop the current game
  def cmd_stop(m, params)
    if @games.has_key? m.channel
      # TODO display statistics
      @games[m.channel].die
      m.reply "Shiritori has stopped. Hope you had fun!"
    else
      # TODO display statistics
      m.reply "No game to stop here, because no game is being played."
    end
  end
  
  # remove the game, so channel messages are no longer processed, and timer removed
  def remove_game(channel)
    @games.delete channel
  end
  
  # all messages from a channel is sent to its shiritori game if any
  def listen(m)
    return unless m.kind_of?(PrivMessage)
    return unless @games.has_key?(m.channel)
    # send the message to the game in the channel to handle it
    @games[m.channel].handle_message m
  end
  
  # remove all games
  def cleanup
    @games.each_key {|g| g.die}
    @games.clear
  end
end

plugin = ShiritoriPlugin.new
plugin.default_auth( 'edit', false )

# Normal commandsi have a stop_gamei have a stop_game
plugin.map 'shiritori stop',
           :action => 'cmd_stop',
           :private => false
# plugin.map 'shiritori set ',
#            :action => 'cmd_set'
#            :private => false
# plugin.map 'shiritori challenge',
#            :action => 'cmd_challenge'
plugin.map 'shiritori [:ruleset]',
           :action => 'cmd_shiritori',
           :defaults => {:ruleset => 'japanese'},
           :private => false
