#-- vim:sw=2:et
#++
#
# :title: Greed dice game plugin for rbot
#
# Author:: Okasu <oka.sux@gmail.com>
#
# Distributed under the same license as rbot itself
#


class Greed < Plugin

  def initialize
    super
    @scoreboard = {}
    @players = []
  end

  def help(plugin, topic="")
    "Simple dice game. Rules: https://en.wikipedia.org/wiki/Greed_(dice_game)"
  end

  SCORING = [
    [ [1,2,3,4,5,6], 1200 ],
    [ [2,2,3,3,4,4], 800 ],
    [ [1]*6, 8000 ],
    [ [1]*5, 4000 ],
    [ [1]*4, 2000 ],
    [ [1]*3, 1000 ],
    [ [1],    100 ],
    [ [2]*6, 1600 ],
    [ [2]*5,  800 ],
    [ [2]*4,  400 ],
    [ [2]*3,  200 ],
    [ [3]*6, 2400 ],
    [ [3]*5, 1200 ],
    [ [3]*4,  600 ],
    [ [3]*3,  300 ],
    [ [4]*6, 3200 ],
    [ [4]*5, 1600 ],
    [ [4]*4,  800 ],
    [ [4]*3,  400 ],
    [ [5]*6, 4000 ],
    [ [5]*5, 2000 ],
    [ [5]*4, 1000 ],
    [ [5]*3,  500 ],
    [ [5],     50 ],
    [ [6]*6, 4800 ],
    [ [6]*5, 2400 ],
    [ [6]*4, 1200 ],
    [ [6]*3,  600 ],
  ]

  def diceroll(ndice=6)
    dice = Array.new
    ndice.times do
      dice << rand(6) + 1
    end
    dice.sort
  end

  def scores
    roll = diceroll
    score = 0
    groups = []
    remain = roll.dup
    SCORING.each do |dice, dscore|
      idx = remain.index(dice.first)
      if idx and remain[idx,dice.size] == dice
        groups << [dice, dscore]
        remain -= dice
        score += dscore
      end
    end
    groups << [remain, 0]
    [roll, score, groups]
  end

  def greed(m, params)
    player = scores
    mhash = {m.sourcenick => player[1]}
    @players.push mhash.to_a[0][0]
    if @players[-1] == @players[-2]
      m.reply _("Oh you, %{who}! You can't go twice in a row!") % {:who => @players[-1]}
      return
    end
    @scoreboard.merge! mhash
    m.reply _("you rolled (%{roll}) for %{pts} points (%{groups})") % {
      :roll => player[0].join(' '),
      :pts => player[1],
      :groups => player[2].map { |d, s| "#{d.join(' ')} => #{s}"}.join(', ')
    }
    if params[:single] == "bot"
      bot = scores
      m.reply _("I rolled (%{roll}) for %{pts} points (%{groups})") % {
        :roll => bot[0].join(' '),
        :pts => bot[1],
        :groups => bot[2].map { |d, s| "#{d.join(' ')} => #{s}"}.join(', ')
      }
      if player[1] < bot[1]
        m.reply _("I win!")
      else
        m.reply _("You win!")
      end
      @players.clear
      return
    end
    if @scoreboard.values.size == 2
      m.reply _("%{who} wins!") % {
        :who => @scoreboard.values[0] > @scoreboard.values[1] ?
                @scoreboard.keys.first : @scoreboard.keys.last
      }
      @scoreboard.clear
      @players.clear
    end
  end
end

plugin = Greed.new
plugin.map "greed :single", :action => :greed, :requirements => {:single => /bot/}, :thread => "yes"
plugin.map "greed", :action => :greed, :thread => "yes"
