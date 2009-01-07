class AutoRejoinPlugin < Plugin
  Config.register Config::BooleanValue.new('rejoin.insult',
    :default => true,
    :desc => "Determines if the bot will insult whoever kicked it, after rejoin")

  def help(plugin, topic="")
    "performs an automatic rejoin if the bot is kicked from a channel"
  end

  def kick(m)
    password = m.channel.mode[:k].value

    if m.address?
      r = rand(10)
      if r > 0
	@bot.timer.add_once(r) {
	  @bot.join m.channel, password
	  @bot.say(m.channel, @bot.lang.get("insult") % m.sourcenick) if @bot.config['rejoin.insult']
	}
      else
	@bot.join m.channel, password
	@bot.say(m.channel, @bot.lang.get("insult") % m.sourcenick) if @bot.config['rejoin.insult']
      end
    end
  end
end

plugin = AutoRejoinPlugin.new
