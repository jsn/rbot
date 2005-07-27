# Play the game of roshambo (rock-paper-scissors)
# Copyright (C) 2004 Hans Fugal
# Distributed under the same license as rbot itself
require 'time'
class RoshamboPlugin < Plugin
  def initialize
    super 
    @scoreboard = {}
  end
  def help(plugin, topic="")
    "roshambo <rock|paper|scissors> => play roshambo"
  end
  def privmsg(m)
    # simultaneity
    choice = choose

    # init scoreboard
    if (not @scoreboard.has_key?(m.sourcenick) or (Time.now - @scoreboard[m.sourcenick]['timestamp']) > 3600)
      @scoreboard[m.sourcenick] = {'me'=>0,'you'=>0,'timestamp'=>Time.now}
    end
    case m.params
    when 'rock','paper','scissors'
      s = score(choice,m.params)
      @scoreboard[m.sourcenick]['timestamp'] = Time.now
      myscore=@scoreboard[m.sourcenick]['me']
      yourscore=@scoreboard[m.sourcenick]['you']
      case s
      when 1
	yourscore=@scoreboard[m.sourcenick]['you'] += 1
	m.reply "#{choice}. You win. Score: me #{myscore} you #{yourscore}"
      when 0
	m.reply "#{choice}. We tie. Score: me #{myscore} you #{yourscore}"
      when -1
	myscore=@scoreboard[m.sourcenick]['me'] += 1
	m.reply "#{choice}! I win! Score: me #{myscore} you #{yourscore}"
      end
    else
      m.reply "incorrect usage: " + help(m.plugin)
    end
  end
      
  def choose
    ['rock','paper','scissors'][rand(3)]
  end
  def score(a,b)
    beats = {'rock'=>'scissors', 'paper'=>'rock', 'scissors'=>'paper'}
    return -1 if beats[a] == b
    return 1 if beats[b] == a
    return 0
  end
end
plugin = RoshamboPlugin.new
plugin.register("roshambo")
plugin.register("rps")
