#-- vim:sw=2:et
#++
#
# :title: Usermodes plugin
#
# Author:: Giuseppe "Oblomov" Bilotta <giuseppe.bilotta@gmail.com>
# Copyright:: (C) 2007 Giuseppe Bilotta
# License:: rbot's licence
#

class UserModesPlugin < Plugin
  Config.register Config::StringValue.new('irc.usermodes',
    :default => '',
    :desc => "User modes to set when connecting to the server")

  def help(plugin, topic="")
    "handles automatic usermode settings on connect. See the config variable irc.usermodes"
  end

  def connect
    modes = @bot.config['irc.usermodes']
    @bot.mode(@bot.nick, modes, '') unless modes.empty?
  end
end

plugin = UserModesPlugin.new
