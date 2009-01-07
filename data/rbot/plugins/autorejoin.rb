#-- vim:sw=2:et
#++
#
# :title: Autorejoin

class AutoRejoinPlugin < Plugin
  Config.register Config::BooleanValue.new('rejoin.insult',
    :default => true,
    :desc => "Determines if the bot will insult whoever kicked it, after rejoin")
  Config.register Config::BooleanValue.new('rejoin.kick',
    :default => false,
    :desc => "Determines if the bot will kick whoever kicked it, after rejoin")

  def initialize
    super
    @should_kick = Hash.new
  end

  def help(plugin, topic="")
    "performs an automatic rejoin if the bot is kicked from a channel"
  end

  def kick(m)
    password = m.channel.mode[:k].value

    if m.address?
      if @bot.config['rejoin.kick']
        @should_kick[m.channel.downcase] = m.sourcenick
      end
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

  def modechange(m)
    # if we got opped on a channel we want to kick somebody from,
    # do the kicking

    # getting opped on a channel is a channel mode change, so bail out if this
    # is not a channel mode change
    return unless m.target.kind_of? Channel
    # bail out if we are not op, too
    return unless @bot.myself.is_op?(m.target)
    # bail out if there's nobody to kick
    to_kick = @should_kick.delete(m.target.downcase)
    return unless to_kick
    # kick the evil user that kicked us
    @bot.kick m.target, to_kick, _("for kicking me out earlier")
  end

end

plugin = AutoRejoinPlugin.new
