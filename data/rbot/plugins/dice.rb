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
  attr_reader :total, :view, :dice
  def initialize(dice, view, total)
    @total = total
    @dice = dice
    @view = view
  end

  def get_view()
    return "["+ dice.to_s + ": " + total.to_s + " | " + view + "] "
  end
end

class DicePlugin < Plugin
  Config.register Config::IntegerValue.new('dice.max_dices',
      :default => 100, :validate => Proc.new{|v| v > 0},
      :desc => "Maximum number of dices to throw.")

  Config.register Config::IntegerValue.new('dice.max_sides',
      :default => 100, :validate => Proc.new{|v| v > 0},
      :desc => "Maximum number of sides per dice.")

  def help(plugin, topic="")
    plugin + " <string> (where <string> is something like: d6 or 2d6 or 2d6+4 or 2d6+1d20 or 2d6+1d5+4d7-3d4-6) => Rolls that set of virtual dice"
  end

  def rolldice(d)
    dice = d.split(/d/)
    repr = []
    r = 0
    unless dice[0] =~ /^[0-9]+/
      dice[0] = 1
    end
    for i in 0...dice[0].to_i
      tmp = rand(dice[1].to_i) + 1
      repr << tmp.to_s
      r = r + tmp
    end
    return DiceDisplay.new(d, repr.join(", "), r)
  end

  def iddice(d)
    dice = d
    porm = d.slice!(0,1)
    if d =~ /d/
      rolled = rolldice(d)
      d = rolled.view
      r = rolled.total
    else
      r = d
    end

    if porm == "-"
      r = 0 - r.to_i
    end

    viewer = DiceDisplay.new(porm + dice, d.to_s, r)
    return viewer
  end

  def privmsg(m)
    # If either not given parameters or given incorrect parameters, return with
    # the help message
    unless(m.params && m.params =~ /^[0-9]*d[0-9]+(\s*[+-]\s*([0-9]+|[0-9]*d[0-9])+)*$/)
      m.nickreply "incorrect usage: " + help(m.plugin)
      return
    end

    # Extract the actual dice request from the message parameters, splitting it
    # into dice and modifiers
    a = m.params.gsub(/\s+/,'').scan(/^[0-9]*d[0-9]+|[+-][0-9]*d[0-9]+|[+-][0-9]+/)
    # check nr of total dices and sides per dice
    nr = 0
    a.each { |dice|
      dc, ds = dice.split(/d/)
      # check sides
      if ds.to_i > @bot.config['dice.max_sides']
       m.reply "sorry, don't have any dices with more than %u sides" % @bot.config['dice.max_sides']
       return
      end
      # We use .max with 1 so that specs such as d6 count as 1 and not as 0
      nr += [dc.to_i, 1].max
    }
    if nr > @bot.config['dice.max_dices']
      m.reply "can't handle more than %u dices" % @bot.config['dice.max_dices']
      return
    end

    # Roll the dice with the extracted request
    rolled = rolldice(a[0])
    r = rolled.total
    t = rolled.get_view()

    # Deal with all the remaining parts of the given dice request
    for i in 1...a.length
      tmp = iddice(a[i])
      r = r + tmp.total.to_i
      t = t + tmp.get_view
    end
    t.chop!
    m.nickreply r.to_s + " || " + m.params + ": " + t
  end
end
plugin = DicePlugin.new
plugin.register("dice")
plugin.register("roll")
##############################################
#fin
