##################
# Filename: dice.rb
# Description: Rbot plugin. Rolls rpg style dice
# Author: David Dorward (http://david.us-lot.org/ - you might find a more up to date version of this plugin there)
# Version: 0.3.2
# Date: Sat 6 Apr 2002
#
# You can get rbot from: http://www.linuxbrit.co.uk/rbot/
#
# Changelog
# 0.1 - Initial release
# 0.1.1 - bug fix, only 1 digit for number of dice sides on first roll
# 0.3.0 - Spelling correction on changelog 0.1.1
#       - Return results of each roll
# 0.3.1 - Minor documentation update
# 0.3.2 - Bug fix, could not subtract numbers (String can't be coerced into Fixnum)
#
# TODO: Test! Test! Test!
#       Comment!
#       Fumble/Critical counter (1's and x's where x is sides on dice)
####################################################

class DiceDisplay
  attr_reader :total, :view
  def initialize(view, total)
    @total = total
    @view = view
  end
end

class DicePlugin < Plugin
  def help(plugin, topic="")
    "dice <string> (where <string> is something like: d6 or 2d6 or 2d6+4 or 2d6+1d20 or 2d6+1d5+4d7-3d4-6) => Rolls that set of virtual dice"
  end

  def rolldice(d)
    dice = d.split(/d/)
    r = 0
    unless dice[0] =~ /^[0-9]+/
      dice[0] = 1
    end
    for i in 0...dice[0].to_i
      r = r + rand(dice[1].to_i) + 1
    end
    return r
  end

  def iddice(d)
    porm = d.slice!(0,1)
    if d =~ /d/
      r = rolldice(d)
    else
      r = d
    end
    if porm == "-"
      r = 0 - r.to_i
    end
    viewer = DiceDisplay.new("[" + porm.to_s + d.to_s + "=" + r.to_s + "] ", r)
    return viewer
  end

  def privmsg(m)
    unless(m.params && m.params =~ /^[0-9]*d[0-9]+([+-]([0-9]+|[0-9]*d[0-9])+)*$/)
      m.reply "incorrect usage: " + help(m.plugin)
      return
    end
    a = m.params.scan(/^[0-9]*d[0-9]+|[+-][0-9]*d[0-9]+|[+-][0-9]+/)
    r = rolldice(a[0])
    t = "[" + a[0].to_s + "=" + r.to_s + "] "
    for i in 1...a.length
      tmp = iddice(a[i])
      r = r + tmp.total.to_i
      t = t + tmp.view.to_s
    end
    m.reply r.to_s + " | " + t
  end
end
plugin = DicePlugin.new
plugin.register("dice")
##############################################
#fin
