#-- vim:sw=2:et
#++
#
# Author: Giuseppe "Oblomov" Bilotta <giuseppe.bilotta@gmail.com>
# Copyright (C) 2006 Giuseppe Bilotta
#
# Based on an idea by hagabaka (Yaohan Chen <yaohan.chen@gmail.com>)
#
# This plugin is used to grab messages from eggdrops (or other bots) that link
# channels from different networks. For the time being, a PRIVMSG echoed by an
# eggdrop is assumed to be in the form:
#    <eggdrop> (nick@network) text of the message
# (TODO make it configurable) and it's fed back to the message delegators.
#
# This plugin also shows how to create 'fake' messages from a plugin, letting
# the bot parse them.
# TODO a possible enhancement to the Irc framework could be to create 'fake'
# servers to make this even easier.
class LinkBot < Plugin
  BotConfig.register BotConfigArrayValue.new('linkbot.nicks',
    :default => [],
    :desc => "Nick(s) of the bots that act as channel links across networks")

  # Initialize the plugin
  def initialize
    super
  end

  # Main method
  def listen(m)
    linkbots = @bot.config['linkbot.nicks']
    return if linkbots.empty?
    return unless linkbots.include?(m.sourcenick)
    return unless m.kind_of?(PrivMessage)
    # Now we know that _m_ is a PRIVMSG from a linkbot. Let's split it
    # in nick, network, message
    if m.message.match(/^\((\w+?)@(\w+?)\)\s+(.*)$/)
      new_nick = $1
      network = $2
      message = $3

      debug "#{m.sourcenick} reports that #{new_nick} said #{message.inspect} on #{network}"
      # One way to pass the new message back to the bot is to create a PrivMessage
      # and delegate it to the plugins
      new_m = PrivMessage.new(@bot, m.server, m.server.user(new_nick), m.target, message)
      @bot.plugins.delegate "listen", new_m
      @bot.plugins.privmsg(new_m) if new_m.address?

      ## Another way is to create a data Hash with source, target and message keys
      ## and then letting the bot client :privmsg handler handle it
      ## Note that this will also create irclog entries for the fake PRIVMSG
      ## TODO we could probably add a :no_irc_log entry to the data passed to the
      ## @bot.client handlers, or something like that
      # data = {
      #   :source => m.server.user(new_nick)
      #   :target => m.target
      #   :message => message
      # }
      # @bot.client[:privmsg].call(data)
    end
  end
end

plugin = LinkBot.new

