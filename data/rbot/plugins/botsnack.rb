#-- vim:sw=2:et
#++
#
# :title: botsnack - give your bot some love
# :version: 1.0a
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
    if m.public?
      m.reply @bot.lang.get("thanks_X") % m.sourcenick
    else
      m.reply @bot.lang.get("thanks")
    end
  end
end

plugin = BotsnackPlugin.new

plugin.map "botsnack", :action => :snack, :thread => "yes" #so it won't lock

