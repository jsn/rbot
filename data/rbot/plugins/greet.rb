#-- vim:sw=2:et
#++
#
# :title: Greet Plugin
#
# Author:: Raine Virta <rane@kapsi.fi>
# Copyright:: (C) 2009 Raine Virta
# License:: GPL v2
#
# Description:: Greet people when they join a channel

class GreetPlugin < Plugin
  Config.register Config::ArrayValue.new('greet.channels',
    :desc => _("Greet people on these channels."),
    :default => [])

  Config.register Config::ArrayValue.new('greet.messages',
    :desc => _("By default, greetings are fetched from lang files. You can use this to specify custom messages, use %s to represent a nick."),
    :default => [])

  Config.register Config::BooleanValue.new('greet.delay',
    :desc => _("Greet with delay so that the greeting seems human-like."),
    :default => false)


  def join(m)
    return unless @bot.config['greet.channels'].include?(m.channel.to_s)

    greeting = if @bot.config['greet.messages'].empty?
      @bot.lang.get("hello_X")
    else
      @bot.config['greet.messages'].pick_one
    end

    msg = Proc.new { @bot.say m.channel, greeting % m.sourcenick }

    if @bot.config['greet.delay']
      @bot.timer.add_once(2+rand(3)) { msg.call }
    else
      msg.call
    end
  end
end

plugin = GreetPlugin.new