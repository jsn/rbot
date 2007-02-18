#-- vim:sw=2:et
#++
#
# :title: Grouphug Plugin for rbot
#
# Author:: Mark Kretschmann <markey@web.de>
# Copyright:: (C) 2005 Mark Kretschmann
# License:: GPL v2

class GrouphugPlugin < Plugin
  def help( plugin, topic="" )
    return "Grouphug plugin. Confess! Usage: 'confess' for random confession, 'confess <number>' for specific one."
  end

  def confess(m, params)
    path = "random"
    path = "confessions/#{params[:num]}" if params[:num]
    begin
      data = @bot.httputil.get_cached(URI.parse("http://grouphug.us/#{path}"))

      reg = Regexp.new( '(<td class="conf-text")(.*?)(<p>)(.*?)(</p>)', Regexp::MULTILINE )
      confession = reg.match( data )[4].ircify_html
      confession = "no confession ##{params[:num]} found" if confession.empty? and params[:num]

      m.reply confession
    rescue
      m.reply "failed to connect to grouphug.us"
    end
  end
end


plugin = GrouphugPlugin.new

plugin.map "grouphug [:num]", :action => :confess, :requirements => { :num => /\d+/ }
plugin.map "confess [:num]", :action => :confess, :requirements => { :num => /\d+/ }

