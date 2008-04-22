#-- vim:sw=2:et
#++
# :title: Config namespace backwards compatibility
#
# The move of everything rbot-related to the Irc::Bot::* namespace from Irc::*
# would cause off-repo plugins to fail if they register any configuration key,
# so we have to handle this case.
#
# Author:: Giuseppe Bilotta (giuseppe.bilotta@gmail.com)

module Irc
  Config = Bot::Config
  module BotConfig
    def BotConfig.register(*args)
      warn "deprecated usage: please use Irc::Bot::Config instead of Irc::BotConfig (e.g. Config.register instead of BotConfig.register, Config::<type>Value instead of BotConfig<type>Value"
      Bot::Config.register(*args)
    end
  end

  Bot::Config.constants.each { |c|
    Irc.module_eval("BotConfig#{c} = Bot::Config::#{c}")
  }
end
