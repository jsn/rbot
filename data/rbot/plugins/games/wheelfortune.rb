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
    ret = self.catclue
    if !@used.empty?
      ret << _(" [Letters called so far: %{red}%{letters}%{nocolor}]") % {
        :red => Irc.color(:red),
        :letters => @used.join(" "),
        :nocolor => Irc.color()
      }
    end
    ret << "\n"
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
  attr_reader :name, :manager, :single, :max, :pending
  attr_writer :running
  attr_accessor :must_buy, :price
  def initialize(name, manager, single, max)
    @name = name.dup
    @manager = manager
    @single = single.to_i
    @max = max.to_i
    @pending = nil
    @qas = []
    @curr_idx = nil
    @running = false
    @scores = Hash.new

    # the default is to make vowels usable only
    # after paying a price in points which is
    # a fraction of the single round score equal
    # to the number of rounds needed to win the game
    # TODO customize
    @must_buy = %w{a e i o u y}
    @price = @single*@single/@max
  end

  def running?
    @running
  end

  def round
    @curr_idx+1 rescue 0
  end

  def buy(user)
    k = user.botuser
    if @scores.key?(k) and @scores[k][:score] >= @price
      @scores[k][:score] -= @price
      return true
    else
      return false
    end
  end

  def score(user)
    k = user.botuser
    if @scores.key?(k)
      @scores[k][:score]
    else
      0
    end
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

  def check(whatever, o={})
    cur = self.current
    return nil unless cur
    if @must_buy.include?(whatever) and not o[:buy]
      return whatever
    end
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
  Config.register Config::StringValue.new('wheelfortune.game_name',
    :default => 'Wheel Of Fortune',
    :desc => "default name of the Wheel Of Fortune game")

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

    if game = @games[ch]
      m.reply _("there's already a %{name} game on %{chan}, managed by %{who}") % {
        :name => game.name,
        :chan => chan,
        :who => game.manager
      }
      return
    end
    name = p[:name].to_s
    if name.empty?
      name = m.source.get_botdata("wheelfortune.game_name") || @bot.config['wheelfortune.game_name']
    else
      m.source.set_botdata("wheelfortune.game_name", name.dup)
    end
    @games[ch] = game = WoFGame.new(name, m.botuser, p[:single], p[:max])
    @bot.say chan, _("%{who} just created a new %{name} game to %{max} points (%{single} per question, %{price} per vowel)") % {
      :name => game.name,
      :who => game.manager,
      :max => game.max,
      :single => game.single,
      :price => game.price
    }
    @bot.say m.source, _("ok, the game has been created. now add clues and answers with \"wof %{chan} [category: <category>,] clue: <clue>, answer: <ans>\". if the clue and answer don't fit in one line, add the answer separately with \"wof %{chan} answer <answer>\"") % {
      :chan => chan
    }
  end

  def setup_qa(m, p)
    ch = p[:chan].irc_downcase(m.server.casemap).intern
    if !@games.key?(ch)
      m.reply _("there's no %{name} game running on %{chan}") % {
        :name => @bot.config['wheelfortune.game_name'],
        :chan => p[:chan]
      }
      return
    end
    game = @games[ch]

    if m.botuser != game.manager and !m.botuser.permit?('wheelfortune::manage::other::add')
      m.reply _("you can't add questions to the %{name} game on %{chan}") % {
        :name => game.name,
        :chan => p[:chan]
      }
    end

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
      m.reply _("there's no %{name} game running on %{chan}") % {
        :name => @bot.config['wheelfortune.game_name'],
        :chan => chan
      }
      return
    end
    game = @games[ch]
    qa = p[:next] ? game.next : game.current
    if !qa
      m.reply _("there are no %{name} questions for %{chan}, I'm waiting for %{who} to add them") % {
        :name => game.name,
        :chan => chan,
        :who => game.manager
      }
      return
    end

    @bot.say chan, _("%{bold}%{color}%{name}%{bold}, round %{count}:%{nocolor} %{qa}") % {
      :bold => Bold,
      :color => Irc.color(:green),
      :name => game.name,
      :count => game.round,
      :nocolor => Irc.color(),
      :qa => qa.announcement,
    }
    game.running = true
  end

  def score_table(chan, game, opts={})
    limit = opts[:limit] || -1
    table = game.score_table[0..limit]
    if table.length == 0
      @bot.say chan, _("no scores")
      return
    end
    nick_wd = table.map { |a| a.first.length }.max
    score_wd = table.first.last.to_s.length
    table.each { |t|
      @bot.say chan, "%*s : %*u" % [nick_wd, t.first, score_wd, t.last]
    }
  end

  def react_on_check(m, ch, game, check)
    debug "check: #{check.inspect}"
    case check
    when nil
      # can this happen?
      warning "game #{game}, qa #{game.current} checked nil against #{m.message}"
      return
    when :used
      # m.reply "STUPID! YOU SO STUPID!"
      return
    when *game.must_buy
      m.nickreply _("You must buy the %{vowel}") % {
        :vowel => check
      }
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
        m.reply _("%{bold}%{color}%{name}%{bold}%{nocolor}: %{who} %{bold}wins%{bold} after %{count} rounds!\nThe final score is") % {
          :bold => Bold,
          :color => Irc.color(:green),
          :who => m.sourcenick,
          :name => game.name,
          :count => game.round,
          :nocolor => Irc.color()
        }
        score_table(m.channel, game)
        @games.delete(ch)
      else :more
        m.reply _("%{bold}%{color}%{name}%{bold}, round %{count}%{nocolor} -- score so far:") % {
          :bold => Bold,
          :color => Irc.color(:green),
          :name => game.name,
          :count => game.round,
          :nocolor => Irc.color()
        }
        score_table(m.channel, game)
        announce(m, :next => true)
      end
    else
      # can this happen?
      warning "game #{game}, qa #{game.current} checked #{check} against #{m.message}"
    end
  end

  def listen(m)
    return unless m.kind_of?(PrivMessage) and not m.address?
    ch = m.channel.irc_downcase(m.server.casemap).intern
    return unless game = @games[ch]
    return unless game.running?
    check = game.check(m.message, :buy => false)
    react_on_check(m, ch, game, check)
  end

  def buy(m, p)
    ch = m.channel.irc_downcase(m.server.casemap).intern
    game = @games[ch]
    if not game
      m.reply _("there's no %{name} game running on %{chan}") % {
        :name => @bot.config['wheelfortune.game_name'],
        :chan => m.channel
      }
      return
    elsif !game.running?
      m.reply _("there are no %{name} questions for %{chan}, I'm waiting for %{who} to add them") % {
        :name => game.name,
        :chan => chan,
        :who => game.manager
      }
      return
    else
      vowel = p[:vowel]
      bought = game.buy(m.source)
      if bought
        m.reply _("%{who} buys a %{vowel} for %{price} points") % {
          :who => m.source,
          :vowel => vowel,
          :price => game.price
        }
        check = game.check(vowel, :buy => true)
        react_on_check(m, ch, game, check)
      else
        m.reply _("you can't buy a %{vowel}, %{who}: it costs %{price} points and you only have %{score}") % {
          :who => m.source,
          :vowel => vowel,
          :price => game.price,
          :score => game.score(m.source)
        }
      end
    end
  end

  def cancel(m, p)
    ch = m.channel.irc_downcase(m.server.casemap).intern
    if !@games.key?(ch)
      m.reply _("there's no %{name} game running on %{chan}") % {
        :name => @bot.config['wheelfortune.game_name'],
        :chan => m.channel
      }
      return
    end
    # is the botuser the manager or allowed to cancel someone else's game?
    if m.botuser == game.manager or m.botuser.permit?('wheelfortune::manage::other::cancel')
      do_cancel(ch)
    else
      m.reply _("you can't cancel the current game")
    end
  end

  def do_cancel(ch)
    game = @games.delete(ch)
    chan = ch.to_s
    @bot.say chan, _("%{name} game cancelled after %{count} rounds. Partial score:") % {
      :name => game.name,
      :count => game.round
    }
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
plugin.map "wof [:chan] play [*name] for :single [points] to :max [points]", :action => 'setup_game'
plugin.map "wof :chan [category: *cat,] clue: *clue[, answer: *ans]", :action => 'setup_qa', :public => false
plugin.map "wof :chan answer: *ans", :action => 'setup_qa', :public => false
plugin.map "wof buy :vowel", :action => 'buy', :requirements => { :vowel => /./u }
