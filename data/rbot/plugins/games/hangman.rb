#-- vim:sw=2:et
#++
#
# :title: Hangman Plugin
#
# Author:: Raine Virta <rane@kapsi.fi>
# Copyright:: (C) 2009 Raine Virta
# License:: GPL v2
#
# Hangman game for rbot

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
    @word    = word.downcase
    @guesses = []
    @misses  = []
    @health  = HEALTH
    @solved  = false
  end

  def letters
    # array of the letters in the word
    @word.split(//).reject { |c| c !~ LETTER  }
  end

  def face
    STAGES[@health]
  end

  def to_s
    @word.split(//).map { |c|
      @guesses.include?(c) || c !~ LETTER  ? c : "_"
    }.join
  end

  def guess(str)
    str.downcase!

    # full word guess
    if str !~ /^#{LETTER}$/
      word == str ? @solved = true : punish
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
    (letters-@guesses).empty? || @solved
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
  end

  def help(plugin, topic="")
    case topic
    when ""
      #plugin.map "hangman [play] [on :channel] [with word :word] [with [:adj] length [:relation :size]]",
      return "hangman game plugin - topics: play, stop"
    when "play"
      return "hangman play [on <channel>] [with word <word>] | hangman play with [max|min] length [<|>|==] [<length>] => start a hangman game -- word will be randomed in case it's omitted"
    when "stop"
      return "hangman stop => quits the current game"
    end
  end

  def start(m, params)
    word = unless params[:word]
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
    else
      params[:word]
    end
    
    return unless word

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
        m.reply "there's already a hangman game in progress on that channel"
        return
      end
      
      @bot.say target, "#{m.source} has started a hangman -- join the fun!"
    else
      target = m.source.to_s
    end
    
    @games[target] = Hangman.new(word)

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

    if (game = @games[source])
      if m.message =~ /^[^\W0-9_]$/u || m.message =~ prepare_guess_regex(game)
        return unless game.guess(m.message)
        
        m.reply game_status(game)
      end

      if game.over?
        if game.won?
          m.reply "game over - you win!"
        elsif game.lost?
          m.reply "game over - you lose!"
        end

        @games.delete(source)
      end
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
plugin.map "hangman [play] [on :channel] [with word :word] [with [:adj] length [:relation :size]]",
  :action => 'start',
  :requirements => { :adj => /min|max/, :relation => /<|<=|>=|>|==/, :size => /\d+/ }
  
plugin.map "hangman stop", :action => 'stop'
