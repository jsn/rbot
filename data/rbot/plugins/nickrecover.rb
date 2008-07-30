#-- vim:sw=2:et
#++
#
# :title: Nick recovery
#
# Author:: Giuseppe "Oblomov" Bilotta <giuseppe.bilotta@gmail.com>
#
# Copyright:: (C) 2008 Giuseppe Bilotta
#
# This plugin tries to automatically recover the bot's wanted nick
# in case it couldn't be achieved.

class NickRecoverPlugin < Plugin
  
  Config.register Config::IntegerValue.new('irc.nick_retry',
    :default => 60, :valiedate => Proc.new { |v| v >= 0 },
    :on_change => Proc.new do |bot, v|
      if v > 0
        bot.plugin['nickrecover'].start_recovery(v)
      else
        bot.plugin['nickrecover'].stop_recovery
      end
    end, :requires_restart => false,
    :desc => _("Time in seconds to wait between attempts to recover the nick"))

  def enabled?
    @bot.config['irc.nick_retry'] > 0
  end

  def poll_time
    @bot.config['irc.nick_retry']
  end

  def wanted_nick
    @bot.wanted_nick
  end

  def stop_recovery
    @bot.timer.remove(@recovery) if @recovery
  end

  def start_recovery(time=self.poll_time)
    if @recovery
      @bot.timer.reschedule(@recovery, poll_time)
    else
      @recovery = @bot.timer.add(time) { @bot.nickchg wanted_nick }
    end
  end

  def initialize
    super
    @recovery = nil
    if enabled? and @bot.nick.downcase != wanted_nick
      start_recovery
    end
  end

  def nick(m)
    return unless m.address?
    # if recovery is enabled and the nick is not the wanted nick,
    # launch the recovery process. Stop it otherwise
    if enabled? and m.newnick.downcase != wanted_nick.downcase
      start_recovery
    else
      stop_recovery
    end
  end

end

plugin = NickRecoverPlugin.new

