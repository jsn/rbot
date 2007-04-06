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

class ::LastFmEvent
  attr_accessor :url, :date, :artist, :location, :attendance
  def initialize(url, date, artist, location, attendance)
    @url = url
    @date = date
    @artist = artist
    @location = location
    @attendance = attendance
  end
end

class LastFmPlugin < Plugin

  LASTFM = "http://www.last.fm"

  def help(plugin, topic="")
    case topic.intern
    when :event, :events
      "lastfm events in <location> => show information on events in or near <location> from last.fm"
    when :artist, :group
      "lastfm artist <name> => show information on artist/group <name> from last.fm"
    when :song, :track
      "lastfm track <name> => show information on track/song <name> from last.fm [not implemented yet]"
    when :album
      "lastfm album <name> => show information on album <name> from last.fm [not implemented yet]"
    else
      "lastfm <function> <user> => lastfm data for <user> on last.fm where <function> in [recenttracks, topartists, topalbums, toptracks, tags, friends, neighbors]. other topics: events, artist, group, song, track, album"
    end
  end

  def lastfm(m, params)
    action = params[:action].intern
    action = :neighbours if action == :neighbors
    what = params[:what]
    case action
    when :events, :event
      page = nil
      begin
        location = what.to_s.sub(/^in\s+/,'')
        raise "wrong location #{location}" if location.empty?
        esc = URI.escape(location)
        page = @bot.httputil.get "#{LASTFM}/events/?findloc=#{esc}"
        if page
          events = Array.new
          disp_events = Array.new

          # matches are:
          # 1. day 2. moth 3. year 4. url_who 5. who 6. url_where 7. where 8. how_many
          pre_events = page.scan(/<tr class="vevent\s+\w+\s+\S+?-(\d\d)-(\d\d)-(\d\d\d\d)\s*">.*?<a class="url summary" href="(\/event\/\d+)">(.*?)<\/a>.*?<a href="(\/venue\/\d+)">(.*?)<\/a>.*?<td class="attendance">(.*?)<\/td>\s+<\/tr>/m)
          # debug pre_events.inspect
          if pre_events.empty?
            m.reply "No events found in #{location}, sorry"
          end
          pre_events.each { |day, month, year, url_who, who, url_where, where, how_many|
            date = Time.utc(year.to_i, month.to_i, day.to_i)
            url = LASTFM + url_who
            if who.match(/<strong>(.*?)<\/strong>(.+)?/)
              artist = Bold + $1.ircify_html + Bold
              artist << ", " << $2.ircify_html if $2
            else
              debug "who: #{who.inspect}"
              artist = who.ircify_html
            end
            if where.match(/<strong>(.*?)<\/strong>(.+)?/)
              loc = Bold + $1.ircify_html + Bold
              loc << ", " << $2.ircify_html if $2
            else
              debug where.inspect
              loc = where.ircify_html
            end
            attendance = how_many.ircify_html
            events << LastFmEvent.new(url, date, artist, loc, attendance)
          }
          # debug events.inspect

          events[0..2].each { |event|
            disp_events << "%s %s @ %s (%s) %s" % [event.date.strftime("%a %b, %d %Y"), event.artist, event.location, event.attendance, event.url]
          }
          m.reply disp_events.join(' | ')
        else
          m.reply "No events found in #{location}"
          return
        end
      rescue Exception => e
        m.reply "I had problems looking for events #{what.to_s}"
        error e.inspect
        debug e.backtrace.join("\n")
        debug page[0...10*1024] if page
        return
      end
    when :artist, :group
      artist = what.to_s
      page = nil
      begin
        esc = URI.escape(artist)
        page = @bot.httputil.get "#{LASTFM}/music/#{esc}"
        if page
          if page.match(/<h1 class="h1artist"><a href="([^"]+)">(.*?)<\/a><\/h1>/)
            url = LASTFM + $1
            title = $2.ircify_html
          else
            raise "No URL/Title found for #{artist}"
          end

          wiki = "This #{action} doesn't have a description yet. You can help by writing it: #{url}/+wiki?action=edit"
          if page.match(/<div class="wikiAbstract">(.*?)<\/div>/m)
            wiki = $1.ircify_html
          end

          m.reply "%s : %s\n%s" % [title, url, wiki]
        else
          m.reply "no data found on #{artist}"
          return
        end
      rescue Exception => e
        m.reply "I had problems looking for #{artist}"
        error e.inspect
        debug e.backtrace.join("\n")
        debug page[0...10*1024] if page
        return
      end
    when :song, :track
      m.reply "not implemented yet, sorry"
    when :album
      m.reply "not implemented yet, sorry"
    else
      return usage(m) unless what.length == 1
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
