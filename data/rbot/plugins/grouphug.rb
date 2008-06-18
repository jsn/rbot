#-- vim:sw=2:et
#++
#
# :title: Grouphug Plugin for rbot
#
# Author:: Mark Kretschmann <markey@web.de>
# Author:: Casey Link <unnamedrambler@gmail.com>
# Copyright:: (C) 2005 Mark Kretschmann
# Copyright:: (C) 2008 Casey Link
# License:: GPL v2

class GrouphugPlugin < Plugin
  def initialize
    super
    @confessions = Array.new
  end

  def help( plugin, topic="" )
    return "Grouphug plugin. Confess! Usage: 'confess' for random confession, 'confess <number>' for specific one."
  end

  def confess(m, params)
    opts = { :cache => false }
    path = "random"
    begin
      # Fetch a specific question - separate from cache
      if params[:num]
        path = "confessions/#{params[:num]}"
        opts.delete(:cache)
        data = @bot.httputil.get("http://grouphug.us/#{path}", opts)

        reg = Regexp.new('<div class="content">.*?<p>(.*?)</p>', Regexp::MULTILINE)
        res = data.scan(reg)
        confession = res[0][0].ircify_html
        confession = "no confession ##{params[:num]} found" if confession.empty? and params[:num]
        m.reply confession
      else # Cache random confessions
        if @confessions.empty?
          data = @bot.httputil.get("http://grouphug.us/#{path}", opts)
          reg = Regexp.new('<div class="content">.*?<p>(.*?)</p>', Regexp::MULTILINE)
          res = data.scan(reg)
          res.each do |quote|
            @confessions << quote[0].ircify_html
          end
        end
        confession = @confessions.pop
        m.reply confession
      end
    rescue
      m.reply "failed to connect to grouphug.us"
    end
  end
end


plugin = GrouphugPlugin.new

plugin.map "grouphug [:num]",
  :thread => true, :action => :confess, :requirements => { :num => /\d+/ }
plugin.map "confess [:num]",
  :thread => true, :action => :confess, :requirements => { :num => /\d+/ }

