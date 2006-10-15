class AutoRejoinPlugin < Plugin
  def help(plugin, topic="")
    "performs an automatic rejoin if the bot is kicked from a channel"
  end
  def kick(m)
    if m.address?
      r = rand(10)
      if r > 0
	@bot.timer.add_once(r, m) {|m|
	  @bot.join m.channel
	  @bot.say m.channel, @bot.lang.get("insult") % m.sourcenick
	}
      else
	@bot.join m.channel
	@bot.say m.channel, @bot.lang.get("insult") % m.sourcenick
      end
    end
  end
end

plugin = AutoRejoinPlugin.new
plugin.register("autorejoin")
