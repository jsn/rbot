class AutoRejoinPlugin < Plugin
  def help(plugin, topic="")
    "performs an automatic rejoin if the bot is kicked from a channel"
  end
  def kick(m)
    if m.address?
      @bot.timer.add_once(10, m) {|m|
        @bot.join m.channel
        @bot.say m.channel, @bot.lang.get("insult") % m.sourcenick
      }
    end
  end
end

plugin = AutoRejoinPlugin.new
plugin.register("autorejoin")
