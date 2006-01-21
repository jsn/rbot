require 'open-uri'

# plugin submitted by Jeremy Voorhis (jvoorhis)

class LastFmPlugin < Plugin
  def help(plugin, topic="")
    "lastfm <function> <user> => lastfm data for <user> on last.fm where <function> in [recenttracks, topartists, topalbums, toptracks, tags, friends, neighbors]"
  end

  def do_lastfm (m, params)
    begin
      if params[:action] == "neighbors" || params[:action] == "neighbours" then
        params[:action]="neighbours"
      end
      data = open("http://ws.audioscrobbler.com/1.0/user/#{params[:user]}/#{params[:action]}.txt")
      m.reply "#{params[:action]} for #{params[:user]}:"
      m.reply data.to_a[0..3].map{|l| l.split(',')[-1].chomp}.join(", ")
    rescue
      m.reply "could not find #{params[:action]} for #{params[:user]} (is #{params[:user]} a user?)"
    end
  end
end

plugin = LastFmPlugin.new
plugin.map 'lastfm :action :user', :action => 'do_lastfm'
