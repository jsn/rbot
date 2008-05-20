#-- vim:sw=2:et
#++
#
# :title: botsnack - give your bot some love
# :version: 1.0
#
# Author:: Jan Wikholm <jw@jw.fi>
#
# Copyright:: (C) 2008 Jan Wikholm
#
# License:: public domain
#
# TODO More replies




class BotsnackPlugin < Plugin

  def help(plugin, topic="")
    "botsnack => reward #{@nick} for being good"
  end


  def snack(m, params)
    # Below is the 0.9.10 version, but I changed it because it would conflict 
    # with config params [core.reply_with_nick true] and [core.nick_postfix ,]
    # resulting in:
    # <@unfo-> .botsnack
    # <@rrBot> unfo-, unfo-: thanks :)
    # OLD: m.reply @bot.lang.get("thanks_X") % m.sourcenick if(m.public?)
    # OLD: m.reply @bot.lang.get("thanks") if(m.private?)
    
    m.reply @bot.lang.get("thanks") 
  end
end

plugin = BotsnackPlugin.new

plugin.map "botsnack", :action => :snack, :thread => "yes" #so it won't lock

