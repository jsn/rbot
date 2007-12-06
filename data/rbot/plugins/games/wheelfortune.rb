#-- vim:sw=2:et
#++
#
# :title: Hangman/Wheel Of Fortune
#
# Author:: Giuseppe "Oblomov" Bilotta <giuseppe.bilotta@gmail.com>
# Copyright:: (C) 2007 Giuseppe Bilotta
# License:: rbot

# Wheel-of-Fortune Question/Answer
class WoFQA
  attr_accessor :cat, :clue, :answer, :hint
  def initialize(cat, clue, ans=nil)
    @cat = cat # category
    @clue = clue # clue phrase
    self.answer = ans
  end

  def catclue
    ret = ""
    ret << "(" + cat + ") " unless cat.empty?
    ret << clue
  end

  def answer=(ans)
    if !ans
      @answer = nil
      @split = []
      @hint = []
      return
    end
    @answer = ans.dup.downcase
    @split = @answer.scan(/./u)
    @hint = @split.inject([]) { |list, ch|
      if ch !~ /[a-z]/
        list << ch
      else
        list << "*"
      end
    }
    @used = []
  end

  def announcement
    ret = self.catclue << "\n"
    ret << _("Letters called so far: ") << @used.join(" ") << "\n" unless @used.empty?
    ret << @hint.join
  end

  def check(ans_or_letter)
    d = ans_or_letter.downcase
    if d == @answer
      return :gotit
    elsif d.length == 1
      if @used.include?(d)
        return :used
      else
        @used << d
        @used.sort!
        if @split.include?(d)
          count = 0
          @split.each_with_index { |c, i|
            if c == d
              @hint[i] = d.upcase
              count += 1
            end
          }
          return count
        else
          return :missing
        end
      end
    else
      return :wrong
    end
  end

end

# Wheel-of-Fortune game
class WoFGame
  attr_reader :manager, :single, :max, :pending
  attr_writer :running
  def initialize(manager, single, max)
    @manager = manager
    @single = single.to_i
    @max = max.to_i
    @pending = nil
    @qas = []
    @curr_idx = nil
    @running = false
    @scores = Hash.new
  end

  def running?
    @running
  end

  def round
    @curr_idx+1 rescue 0
  end

  def mark_winner(user)
    @running = false
    k = user.botuser
    if @scores.key?(k)
      @scores[k][:nick] = user.nick
      @scores[k][:score] += @single
    else
      @scores[k] = { :nick => user.nick, :score => @single }
    end
    if @scores[k][:score] >= @max
      return :done
    else
      return :more
    end
  end

  def score_table
    table = []
    @scores.each { |k, val|
      table << ["%s (%s)" % [val[:nick], k], val[:score]]
    }
    table.sort! { |a, b| b.last <=> a.last }
  end

  def current
    return nil unless @curr_idx
    @qas[@curr_idx]
  end

  def next
    # don't advance if there are no further QAs
    return nil if @curr_idx == @qas.length - 1
    if @curr_idx
      @curr_idx += 1
    else
      @curr_idx = 0
    end
    return current
  end

  def check(whatever)
    cur = self.current
    return nil unless cur
    return cur.check(whatever)
  end

  def start_add_qa(cat, clue)
    return [nil, @pending] if @pending
    @pending = WoFQA.new(cat.dup, clue.dup)
    return [true, @pending]
  end

  def finish_add_qa(ans)
    return nil unless @pending
    @pending.answer = ans.dup
    @qas << @pending
    @pending = nil
    return @qas.last
  end
end

class WheelOfFortune < Plugin
  def initialize
    super
    # TODO load/save running games?
    @games = Hash.new
  end

  def setup_game(m, p)
    chan = p[:chan] || m.channel
    if !chan
      m.reply _("you must specify a channel")
      return
    end
    ch = chan.irc_downcase(m.server.casemap).intern

    if @games.key?(ch)
      m.reply _("there's already a Wheel-of-Fortune game on %{chan}, managed by %{who}") % {
        :chan => chan,
        :who => @games[ch].manager
      }
      return
    end
    @games[ch] = game = WoFGame.new(m.botuser, p[:single], p[:max])
    @bot.say chan, _("%{who} just created a new Wheel-of-Fortune game to %{max} points (%{single} per question)") % {
      :who => game.manager,
      :max => game.max,
      :single => game.single
    }
    @bot.say m.source, _("ok, the game has been created. now add clues and answers with \"wof %{chan} [category: <category>,] clue: <clue>, answer: <ans>\". if the clue and answer don't fit in one line, add the answer separately with \"wof %{chan} answer <answer>\"") % {
      :chan => chan
    }
  end

  def setup_qa(m, p)
    ch = p[:chan].irc_downcase(m.server.casemap).intern
    if !@games.key?(ch)
      m.reply _("there's no Wheel-of-Fortune game running on %{chan}") % {
        :chan => p[:chan]
      }
      return
    end
    game = @games[ch]
    cat = p[:cat].to_s
    clue = p[:clue].to_s
    ans = p[:ans].to_s
    if ans.include?('*')
      m.reply _("sorry, the answer cannot contain the '*' character")
      return
    end

    if !clue.empty?
      worked, qa = game.start_add_qa(cat, clue)
      if worked
        str = ans.empty? ?  _("ok, new clue added for %{chan}: %{catclue}") : nil
      else
        str = _("there's already a pending clue for %{chan}: %{catclue}")
      end
      m.reply _(str) % { :chan => p[:chan], :catclue => qa.catclue } if str
      return unless worked or !ans.empty?
    end
    if !ans.empty?
      qa = game.finish_add_qa(ans)
      if qa
        str = _("ok, new QA added for %{chan}: %{catclue} => %{ans}")
      else
        str = _("there's no pending clue for %{chan}!")
      end
      m.reply _(str) % { :chan => p[:chan], :catclue => qa ? qa.catclue : nil, :ans => qa ? qa.answer : nil}
      announce(m, p.merge({ :next => true }) ) unless game.running?
    else
      m.reply _("something went wrong, I can't seem to understand what you're trying to set up")
    end
  end

  def announce(m, p={})
    chan = p[:chan] || m.channel
    ch = chan.irc_downcase(m.server.casemap).intern
    if !@games.key?(ch)
      m.reply _("there's no Wheel-of-Fortune game running on %{chan}") % { :chan => p[:chan] }
      return
    end
    game = @games[ch]
    qa = p[:next] ? game.next : game.current
    if !qa
      m.reply _("there are no Wheel-of-Fortune questions for %{chan}, I'm waiting for %{who} to add them") % {
        :chan => chan,
        :who => game.manager
      }
      return
    end

    @bot.say chan, qa.announcement
    game.running = true
  end

  def score_table(chan, game, opts={})
    limit = opts[:limit] || -1
    table = game.score_table[0..limit]
    nick_wd = table.map { |a| a.first.length }.max
    score_wd = table.first.last.to_s.length
    table.each { |t|
      @bot.say chan, "%*s : %*u" % [nick_wd, t.first, score_wd, t.last]
    }
  end

  def listen(m)
    return unless m.kind_of?(PrivMessage) and not m.address?
    ch = m.channel.irc_downcase(m.server.casemap).intern
    return unless game = @games[ch]
    return unless game.running?
    check = game.check(m.message)
    debug "check: #{check.inspect}"
    case check
    when nil
      # can this happen?
      warning "game #{game}, qa #{game.current} checked nil against #{m.message}"
      return
    when :used
      # m.reply "STUPID! YOU SO STUPID!"
      return
    when :wrong
      return
    when Numeric, :missing
      # TODO may alter score depening on how many letters were guessed
      # TODO what happens when the last hint reveals the whole answer?
      announce(m)
    when :gotit
      want_more = game.mark_winner(m.source)
      m.reply _("%{who} got it! The answer was: %{ans}") % {
        :who => m.sourcenick,
        :ans => game.current.answer
      }
      if want_more == :done
        # max score reached
        m.reply _("%{who} wins the game after %{count} rounds!") % {
          :who => m.sourcenick,
          :count => game.round
        }
        score_table(m.channel, game)
        @games.delete(ch)
      else :more
        score_table(m.channel, game)
        announce(m, :next => true)
      end
    else
      # can this happen?
      warning "game #{game}, qa #{game.current} checked #{check} against #{m.message}"
    end
  end

  def cancel(m, p)
    ch = m.channel.irc_downcase(m.server.casemap).intern
    if !@games.key?(ch)
      m.reply _("there's no Wheel-of-Fortune game running on %{chan}") % {
        :chan => m.channel
      }
      return
    end
    do_cancel(ch)
  end

  def do_cancel(ch)
    game = @games.delete(ch)
    chan = ch.to_s
    @bot.say chan, _("Wheel-of-Fortune game cancelled after %{count} rounds. Partial score:")
    score_table(chan, game)
  end

  def cleanup
    @games.each_key { |k| do_cancel(k) }
    super
  end
end

plugin = WheelOfFortune.new

plugin.map "wof", :action => 'announce', :private => false
plugin.map "wof cancel", :action => 'cancel', :private => false
plugin.map "wof [:chan] play for :single [points] to :max [points]", :action => 'setup_game'
plugin.map "wof :chan [category: *cat,] clue: *clue[, answer: *ans]", :action => 'setup_qa', :public => false
plugin.map "wof :chan answer: *ans", :action => 'setup_qa', :public => false
