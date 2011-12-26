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
  end

  def help(plugin, topic="")
    "Simple dice game. Rules: https://en.wikipedia.org/wiki/Greed_(dice_game)"
  end

  def diceroll
    dice = Array.new
    for i in 0..5 do
      dice[i] = rand(6) + 1
    end
    dice
  end

  def scores
    roll = diceroll
    one =  two = three = four = five = six = score = 0
    roll.each do |x|
      case x
      when 1
        one += 1
        if one == 3
          score += 1000
        elsif one == 6
          score += 7000
        else
          score += 100
        end
      when 2
        two += 1
        if two == 3
          score += 200
        elsif two == 4
          score += 400
        end
      when 3
        three += 1
        if three == 3
          score += 300
        elsif three == 5
          score += 1200
        end
      when 4
        four += 1
        if four == 3
          score += 400
        elsif four == 6
          score += 3600
        end
      when 5
        five += 1
        if five == 3
          score += 500
        else
          score += 50
        end
      when 6
        six += 6
        if six == 3
          score += 600
        end
      end
    end
    if roll.sort == [1,2,3,4,5,6]
      score = 1200
    elsif roll.sort == [2,2,3,3,4,4]
      score = 800
    end
    [score, roll]
  end

  def greed(m, params)
    player = scores
    mhash = {m.sourcenick => player[0]}
    @scoreboard.merge! mhash
    m.reply "You have #{player[0]} points. (#{player[1].join("-")})"
    if params[:single] == "bot"
      bot = scores
      m.reply "I have #{bot[0]} points. (#{bot[1].join("-")})"
      if player[0] < bot[0]
        m.reply "Bot wins!"
      else
        m.reply "Human player wins!"
      end
    end
    if @scoreboard.values.size == 2
      if @scoreboard.values[0] > @scoreboard.values[1]
        m.reply "#{@scoreboard.keys.first} wins!"
      else
        m.reply "#{@scoreboard.keys.last} wins!"
      end
    @scoreboard.clear
    end
  end
end

plugin = Greed.new
plugin.map "greed :single", :action => :greed, :requirements => {:single => /bot/}, :thread => "yes"
plugin.map "greed", :action => :greed, :thread => "yes"
