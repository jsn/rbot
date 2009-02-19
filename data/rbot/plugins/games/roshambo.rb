#-- vim:sw=2:et
#++
#
# :title: Roshambo (rock-paper-scissors) plugin for rbot
#
# Author:: Hans Fugal
# Copyright:: (C) 2004 Hans Fugal
#
# Play the game of roshambo (rock-paper-scissors)
#
# Distributed under the same license as rbot itself

require 'time'

class RoshamboPlugin < Plugin

  def initialize
    super
    @scoreboard = {}
    @beats = { :rock => :scissors, :paper => :rock, :scissors => :paper}
    @plays = @beats.keys
  end

  def help(plugin, topic="")
    "roshambo <rock|paper|scissors> or rps <rock|paper|scissors> => play roshambo"
  end

  def rps(m, params)
    # simultaneity
    bot_choice = @plays.pick_one

    # init scoreboard
    if not @scoreboard.has_key?(m.sourcenick) or (Time.now - @scoreboard[m.sourcenick]['timestamp']) > 3600
      @scoreboard[m.sourcenick] = { 'me' => 0, 'you' => 0, 'timestamp' => Time.now }
    end
    human_choice = params[:play].to_sym
    s = score(bot_choice, human_choice)
    @scoreboard[m.sourcenick]['timestamp'] = Time.now
    myscore=@scoreboard[m.sourcenick]['me']
    yourscore=@scoreboard[m.sourcenick]['you']
    case s
    when 1
      yourscore = @scoreboard[m.sourcenick]['you'] += 1
      m.reply "#{bot_choice}. You win. Score: me #{myscore} you #{yourscore}"
    when 0
      m.reply "#{bot_choice}. We tie. Score: me #{myscore} you #{yourscore}"
    when -1
      myscore = @scoreboard[m.sourcenick]['me'] += 1
      m.reply "#{bot_choice}! I win! Score: me #{myscore} you #{yourscore}"
    end
  end

  def score(bot_choice, human_choice)
    return -1 if @beats[bot_choice] == human_choice
    return 1 if @beats[human_choice] == bot_choice
    return 0
  end
end

plugin = RoshamboPlugin.new
plugin.map "roshambo :play", :action => :rps, :requirements => { :play => /rock|paper|scissors/ }
plugin.map "rps :play", :action => :rps, :requirements => { :play => /rock|paper|scissors/ }
