#-- vim:sw=2:et
#++
#
# :title: lastfm plugin for rbot
#
# Author:: Jeremy Voorhis
# Author:: Giuseppe "Oblomov" Bilotta <giuseppe.bilotta@gmail.com>
#
# Copyright:: (C) 2005 Jeremy Voorhis
# Copyright:: (C) 2007 Giuseppe Bilotta
#
# License:: GPL v2

require 'open-uri'

class LastFmPlugin < Plugin

  LASTFM = "http://www.last.fm"

  def help(plugin, topic="")
    case topic.intern
    when :artist, :group
      "lastfm artist <name> => show information on artist/group <name> from last.fm"
    when :song, :track
      "lastfm track <name> => show information on track/song <name> from last.fm [not implemented yet]"
    when :album
      "lastfm album <name> => show information on album <name> from last.fm"
    else
      "lastfm <function> <user> => lastfm data for <user> on last.fm where <function> in [recenttracks, topartists, topalbums, toptracks, tags, friends, neighbors]. other topics: artist, group, song, track, album"
    end
  end

  def lastfm(m, params)
    action = params[:action].intern
    action = :neighbours if action == :neighbors
    what = params[:what]
    case action
    when :artist, :group
      artist = what.to_s
      begin
        esc = URI.escape(artist)
        page = @bot.httputil.get "#{LASTFM}/music/#{esc}"
        if page
          if page.match(/<h1 class="h1artist"><a href="([^"]+)">(.*?)<\/a><\/h1>/)
            url = LASTFM + $1
            title = $2
          else
            raise "No URL/Title found for #{artist}"
          end

          wiki = page.match(/<div class="wikiAbstract">(.*?)<\/div>/m)[1].ircify_html
          m.reply "%s : %s\n%s" % [title, url, wiki]
        else
          m.reply "no data found on #{artist}"
        end
      rescue
        m.reply "I had problems looking for #{artist}"
        debug page
        return
      end
    when :song, :track
      m.reply "not implemented yet, sorry"
    when :album
      m.reply "not implemented yet, sorry"
    else
      return usage unless what.length == 1
      user = what.first
      begin
        data = open("http://ws.audioscrobbler.com/1.0/user/#{user}/#{action}.txt")
        m.reply "#{action} for #{user}:"
        m.reply data.to_a[0..3].map{|l| l.split(',',2)[-1].chomp}.join(", ")
      rescue
        m.reply "could not find #{action} for #{user} (is #{user} a user?)"
      end
    end
  end
end

plugin = LastFmPlugin.new
plugin.map 'lastfm :action *what'
