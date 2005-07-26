# Author: novex, daniel@novex.net.nz based on code from slap.rb by oct

class EightBallPlugin < Plugin
  def initialize
    super
    @answers=['yes', 'no', 'outlook not so good', 'all signs point to yes', 'all signs point to no', 'why the hell are you asking me?', 'the answer is unclear']
  end
  def help(plugin, topic="")
    "magic 8-ball ruby bot module written by novex for nvinfo on #dumber@quakenet, usage:<botname> 8ball will i ever beat this cancer?"
  end
  def eightball(m, params)
    answers = @answers[rand(@answers.length)]
    action = "shakes the magic 8-ball... #{answers}"
    @bot.action m.replyto, action
  end
end
plugin = EightBallPlugin.new
plugin.map '8ball', :action => 'usage'
plugin.map '8ball *params', :action => 'eightball'
