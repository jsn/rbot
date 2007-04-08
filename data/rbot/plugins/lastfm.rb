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

  def compact_display
    if @attendance.empty?
      return "%s %s @ %s %s" % [@date.strftime("%a %b, %d %Y"), @artist, @location, @url]
    else
      return "%s %s @ %s (%s) %s" % [@date.strftime("%a %b, %d %Y"), @artist, @location, @attendance, @url]
    end
  end
  alias :to_s :compact_display

end

class LastFmPlugin < Plugin
  BotConfig.register BotConfigIntegerValue.new('lastfm.max_events',
    :default => 25, :validate => Proc.new{|v| v > 1},
    :desc => "Maximum number of events to display.")
  BotConfig.register BotConfigIntegerValue.new('lastfm.default_events',
    :default => 3, :validate => Proc.new{|v| v > 1},
    :desc => "Default number of events to display.")

  LASTFM = "http://www.last.fm"

  def help(plugin, topic="")
    case topic.intern
    when :event, :events
      "lastfm [<num>] events in <location> => show information on events in or near <location>. lastfm [<num>] events by <artist/group> => show information on events by <artist/group>. The number of events <num> that can be displayed is optional, defaults to #{@bot.config['lastfm.default_events']} and cannot be higher than #{@bot.config['lastfm.max_events']}"
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

  def find_event(m, params)
    num = params[:num] || @bot.config['lastfm.default_events']
    num = num.to_i.clip(1, @bot.config['lastfm.max_events'])

    location = artist = nil
    location = params[:location].to_s if params[:location]
    artist = params[:who].to_s if params[:who]
    page = nil
    spec = location ? "in #{location}" : "by #{artist}"
    begin
      if location
        esc = CGI.escape(location)
        page = @bot.httputil.get "#{LASTFM}/events/?findloc=#{esc}"
      else
        esc = CGI.escape(artist)
        page = @bot.httputil.get "#{LASTFM}/events?s=#{esc}&findloc="
      end

      if page
        events = Array.new
        disp_events = Array.new

        # matches are:
        # 1. day 2. moth 3. year 4. url_who 5. who 6. url_where 7. where 8. how_many
        pre_events = page.scan(/<tr class="vevent\s+\w+\s+\S+?-(\d\d)-(\d\d)-(\d\d\d\d)\s*">.*?<a class="url summary" href="(\/event\/\d+)">(.*?)<\/a>.*?<a href="(\/venue\/\d+)">(.*?)<\/a>.*?<td class="attendance">(.*?)<\/td>\s+<\/tr>/m)
        # debug pre_events.inspect
        if pre_events.empty?
          m.reply "No events found #{spec}, sorry"
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
          if where.match(/<strong>(.*?)<\/strong>(?:<br\s*\/>(.+)?)?/)
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

        events[0...num].each { |event|
          disp_events << event.to_s
        }
        m.reply disp_events.join(' | '), :split_at => /\s+\|\s+/
      else
        m.reply "No events found #{spec}"
        return
      end
    rescue Exception => e
      m.reply "I had problems looking for events #{spec}"
      error e.inspect
      debug e.backtrace.join("\n")
      debug page[0...10*1024] if page
      return
    end
  end

  def find_artist(m, params)
    artist = params[:who].to_s
    page = nil
    begin
      esc = URI.escape(CGI.escape(artist))
      page = @bot.httputil.get "#{LASTFM}/music/#{esc}"
      if page
        if page.match(/<h1 class="h1artist"><a href="([^"]+)">(.*?)<\/a><\/h1>/)
          url = LASTFM + $1
          title = $2.ircify_html
        else
          raise "No URL/Title found for #{artist}"
        end

        wiki = "This artist doesn't have a description yet. You can help by writing it: #{url}/+wiki?action=edit"
        if page.match(/<div class="wikiAbstract">(.*?)<\/div>/m)
          wiki = $1.ircify_html
        end

        m.reply "%s : %s\n%s" % [title, url, wiki], :overlong => :truncate
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
  end

  def find_track(m, params)
    m.reply "not implemented yet, sorry"
  end

  def find_album(m, params)
    m.reply "not implemented yet, sorry"
  end

  def lastfm(m, params)
    action = params[:action].intern
    action = :neighbours if action == :neighbors
    user = params[:user]
    begin
      data = open("http://ws.audioscrobbler.com/1.0/user/#{user}/#{action}.txt")
      m.reply "#{action} for #{user}:"
      m.reply data.to_a[0..3].map{|l| l.split(',',2)[-1].chomp}.join(", ")
    rescue
      m.reply "could not find #{action} for #{user} (is #{user} a user?)"
    end
  end
end

plugin = LastFmPlugin.new
plugin.map 'lastfm [:num] event[s] in *location', :action => :find_event, :requirements => { :num => /\d+/ }
plugin.map 'lastfm [:num] event[s] by *who', :action => :find_event, :requirements => { :num => /\d+/ }
plugin.map 'lastfm [:num] event[s] [for] *who', :action => :find_event, :requirements => { :num => /\d+/ }
plugin.map 'lastfm artist *who', :action => :find_artist
plugin.map 'lastfm group *who', :action => :find_artist
plugin.map 'lastfm track *dunno', :action => :find_track
plugin.map 'lastfm song *dunno', :action => :find_track
plugin.map 'lastfm album *dunno', :action => :find_album
plugin.map 'lastfm :action *user'
