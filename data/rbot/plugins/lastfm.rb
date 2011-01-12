#-- vim:sw=2:et
#++
#
# :title: lastfm plugin for rbot
#
# Author:: Jeremy Voorhis
# Author:: Giuseppe "Oblomov" Bilotta <giuseppe.bilotta@gmail.com>
# Author:: Casey Link <unnamedrambler@gmail.com>
# Author:: Raine Virta <rane@kapsi.fi>
#
# Copyright:: (C) 2005 Jeremy Voorhis
# Copyright:: (C) 2007 Giuseppe Bilotta
# Copyright:: (C) 2008 Casey Link
# Copyright:: (C) 2009 Raine Virta
#
# License:: GPL v2

require 'rexml/document'
require 'cgi'

class ::LastFmEvent
  attr_reader :attendance, :date

  def initialize(hash)
    @url = hash[:url]
    @date = hash[:date]
    @location = hash[:location]
    @description = hash[:description]
    @attendance = hash[:attendance]

    @artists = hash[:artists]

    if @artists.length > 10 #more than 10 artists and it floods
      diff = @artists.length - 10
      @artist_string = Bold + @artists[0..10].join(', ') + Bold
      @artist_string << _(" and %{n} more...") % {:n => diff}
    else
      @artist_string = Bold + @artists.join(', ') + Bold
    end
  end

  def compact_display
   unless @attendance.zero?
     return "%s %s @ %s (%s attending) %s" % [@date.strftime("%a, %b %d"), @artist_string, @location, @attendance, @url]
   end
   return "%s %s @ %s %s" % [@date.strftime("%a, %b %d"), @artist_string, @location, @url]
  end
  alias :to_s :compact_display

end

define_structure :LastFmVenue, :id, :city, :street, :postal, :country, :name, :url, :lat, :long
class ::Struct::LastFmVenue
  def to_s
    str = self.name.dup
    if self.country
      str << " (" << [self.city, self.country].compact.join(", ") << ")"
    end
    str
  end
end

class LastFmPlugin < Plugin
  include REXML
  Config.register Config::IntegerValue.new('lastfm.max_events',
    :default => 25, :validate => Proc.new{|v| v > 1},
    :desc => "Maximum number of events to display.")
  Config.register Config::IntegerValue.new('lastfm.default_events',
    :default => 3, :validate => Proc.new{|v| v > 1},
    :desc => "Default number of events to display.")
  Config.register Config::IntegerValue.new('lastfm.max_shouts',
    :default => 5, :validate => Proc.new{|v| v > 1},
    :desc => "Maximum number of user shouts to display.")
  Config.register Config::IntegerValue.new('lastfm.default_shouts',
    :default => 3, :validate => Proc.new{|v| v > 1},
    :desc => "Default number of user shouts to display.")
  Config.register Config::IntegerValue.new('lastfm.max_user_data',
    :default => 25, :validate => Proc.new{|v| v > 1},
    :desc => "Maximum number of user data entries (except events and shouts) to display.")
  Config.register Config::IntegerValue.new('lastfm.default_user_data',
    :default => 10, :validate => Proc.new{|v| v > 1},
    :desc => "Default number of user data entries (except events and shouts) to display.")

  APIKEY = "b25b959554ed76058ac220b7b2e0a026"
  APIURL = "http://ws.audioscrobbler.com/2.0/?api_key=#{APIKEY}&"

  def initialize
    super
    class << @registry
      def store(val)
        val
      end
      def restore(val)
        val
      end
    end
  end

  def help(plugin, topic="")
    period = _(", where <period> can be one of: 3|6|12 months, a year")
    case (topic.intern rescue nil)
    when :event, :events
      _("lastfm [<num>] events in <location> => show information on events in or near <location>. lastfm [<num>] events by <artist/group> => show information on events by <artist/group>. lastfm [<num>] events at <venue> => show information on events at specific <venue>. The number of events <num> that can be displayed is optional, defaults to %{d} and cannot be higher than %{m}. Append 'sort by <what> [in <order> order]' to sort events. Events can be sorted by attendance or date (default) in ascending or descending order.") % {:d => @bot.config['lastfm.default_events'], :m => @bot.config['lastfm.max_events']}
    when :artist
      _("lastfm artist <name> => show information on artist <name> from last.fm")
    when :album
      _("lastfm album <name> => show information on album <name> from last.fm [not implemented yet]")
    when :track
      _("lastfm track <name> => search tracks matching <name> on last.fm")
    when :now, :np
      _("lastfm now [<nick>] => show the now playing track from last.fm. np [<nick>] does the same.")
    when :set
      _("lastfm set user <user> => associate your current irc nick with a last.fm user. lastfm set verb <present>, <past> => set your preferred now playing/just played verbs. default \"is listening to\" and \"listened to\".")
    when :who
      _("lastfm who [<nick>] => show who <nick> is on last.fm. if <nick> is empty, show who you are on lastfm.")
    when :compare
      _("lastfm compare [<nick1>] <nick2> => show musical taste compatibility between nick1 (or user if omitted) and nick2")
    when :shouts
      _("lastfm shouts [<nick>] => show shouts to <nick>")
    when :friends
      _("lastfm friends [<nick>] => show <nick>'s friends")
    when :neighbors, :neighbours
      _("lastfm neighbors [<nick>] => show people who share similar musical taste as <nick>")
    when :lovedtracks
      _("lastfm loved[tracks] [<nick>] => show tracks that <nick> has loved")
    when :recenttracks, :recentracks
      _("lastfm recent[tracks] [<nick>] => show tracks that <nick> has recently played")
    when :topalbums
      _("lastfm topalbums [<nick>] [over <period>] => show <nick>'s top albums%{p}") % { :p => period }
    when :topartists
      _("lastfm topartists [<nick>] [over <period>] => show <nick>'s top artists%{p}") % { :p => period }
    when :toptracks
      _("lastfm toptracks [<nick>] [over <period>] => show <nick>'s top tracks%{p}") % { :p => period }
    when :weeklyalbumchart
      _("lastfm weeklyalbumchart [<nick>] => show <nick>'s weekly album chart")
    when :weeklyartistchart
      _("lastfm weeklyartistchart [<nick>] => show <nick>'s weekly artist chart")
    when :weeklytrackchart
      _("lastfm weeklyartistchart [<nick>] => show <nick>'s weekly track chart")
    else
      _("last.fm plugin - topics: events, artist, album, track, now, set, who, compare, shouts, friends, neighbors, (loved|recent)tracks, top(albums|tracks|artists), weekly(album|artist|track)chart")
    end
  end

  # TODO allow searching by country etc.
  #
  # Options: name, limit
  def search_venue_by(options)
    params = {}
    params[:venue] = CGI.escape(options[:name])
    options.delete(:name)
    params.merge!(options)

    uri = "#{APIURL}method=venue.search&"
    uri << params.to_a.map {|e| e.join("=")}.join("&")

    xml = @bot.httputil.get_response(uri)
    doc = Document.new xml.body
    results = []

    doc.root.elements.each("results/venuematches/venue") do |v|
      venue = LastFmVenue.new
      venue.id      = v.elements["id"].text.to_i
      venue.url     = v.elements["url"].text
      venue.lat     = v.elements["location/geo:point/geo:lat"].text.to_f
      venue.long    = v.elements["location/geo:point/geo:long"].text.to_f
      venue.name    = v.elements["name"].text
      venue.city    = v.elements["location/city"].text
      venue.street  = v.elements["location/street"].text
      venue.postal  = v.elements["location/postalcode"].text
      venue.country = v.elements["location/country"].text

      results << venue
    end
    results
  end

  def find_events(m, params)
    num = params[:num] || @bot.config['lastfm.default_events']
    num = num.to_i.clip(1, @bot.config['lastfm.max_events'])

    sort_by    = params[:sort_by] || :date
    sort_order = params[:sort_order]
    sort_order = sort_order.to_sym unless sort_order.nil?

    location = params[:location]
    artist = params[:who]
    venue = params[:venue]
    user = resolve_username(m, params[:user])

    if location
      uri = "#{APIURL}method=geo.getevents&location=#{CGI.escape location.to_s}"
      emptymsg = _("no events found in %{location}") % {:location => location.to_s}
    elsif venue
      begin
        venues = search_venue_by(:name => venue.to_s, :limit => 1)
      rescue Exception => err
        error err
        m.reply _("an error occurred looking for venue %{venue}: %{e}") % {
          :venue => venue.to_s,
          :e => err.message
        }
      end

      if venues.empty?
        m.reply _("no venue found matching %{venue}") % {:venue => venue.to_s}
        return
      end
      venue  = venues.first
      uri = "#{APIURL}method=venue.getevents&venue=#{venue.id}"
      emptymsg = _("no events found at %{venue}") % {:venue => venue.to_s}
    elsif artist
      uri = "#{APIURL}method=artist.getevents&artist=#{CGI.escape artist.to_s}"
      emptymsg = _("no events found by %{artist}") % {:artist => artist.to_s}
    elsif user
      uri = "#{APIURL}method=user.getevents&user=#{CGI.escape user}"
      emptymsg = _("%{user} is not attending any events") % {:user => user}
    end
    xml = @bot.httputil.get_response(uri)

    doc = Document.new xml.body
    if xml.class == Net::HTTPInternalServerError
      if doc.root and doc.root.attributes["status"] == "failed"
        m.reply doc.root.elements["error"].text
      else
        m.reply _("could not retrieve events")
      end
    end
    disp_events = Array.new
    events = Array.new
    doc.root.elements.each("events/event"){ |e|
      h = {}
      h[:title] = e.elements["title"].text
      venue = e.elements["venue"].elements["name"].text
      city = e.elements["venue"].elements["location"].elements["city"].text
      country =  e.elements["venue"].elements["location"].elements["country"].text
      h[:location] = Underline + venue + Underline + " #{Bold + city + Bold}, #{country}"
      date = e.elements["startDate"].text.split
      h[:date] = Time.utc(date[3].to_i, date[2], date[1].to_i)
      h[:desc] = e.elements["description"].text
      h[:url] = e.elements["url"].text
      h[:attendance] = e.elements["attendance"].text.to_i
      artists = Array.new
      e.elements.each("artists/artist"){ |a|
        artists << a.text
      }
      h[:artists] = artists
      events << LastFmEvent.new(h)
    }
    if events.empty?
      m.reply emptymsg
      return
    end

    # sort order when sorted by date is ascending by default
    # and descending when sorted by attendance
    case sort_by.to_sym
    when :attendance
      events = events.sort_by { |e| e.attendance }.reverse
      events.reverse! if [:ascending, :asc].include? sort_order
    when :date
      events = events.sort_by { |e| e.date }
      events.reverse! if [:descending, :desc].include? sort_order
    end

    events[0...num].each { |event|
      disp_events << event.to_s
    }
    m.reply disp_events.join(' | '), :split_at => /\s+\|\s+/

  end

  def tasteometer(m, params)
    opts = { :cache => false }
    user1 = resolve_username(m, params[:user1])
    user2 = resolve_username(m, params[:user2])
    xml = @bot.httputil.get_response("#{APIURL}method=tasteometer.compare&type1=user&type2=user&value1=#{CGI.escape user1}&value2=#{CGI.escape user2}", opts)
    doc = Document.new xml.body
    unless doc
      m.reply _("last.fm parsing failed")
      return
    end
    if xml.class == Net::HTTPBadRequest
      if doc.root.elements["error"].attributes["code"] == "7" then
        error = doc.root.elements["error"].text
        error.match(/Invalid username: \[(.*)\]/);
        baduser = $1

        m.reply _("%{u} doesn't exist on last.fm") % {:u => baduser}
        return
      else
        m.reply _("error: %{e}") % {:e => doc.root.element["error"].text}
        return
      end
    end
    score = doc.root.elements["comparison/result/score"].text.to_f
    artists = doc.root.get_elements("comparison/result/artists/artist").map { |e| e.elements["name"].text}
    case
      when score >= 0.9
        rating = _("Super")
      when score >= 0.7
        rating = _("Very High")
      when score >= 0.5
        rating = _("High")
      when score >= 0.3
        rating = _("Medium")
      when score >= 0.1
        rating = _("Low")
      else
        rating = _("Very Low")
    end

    common_artists = unless artists.empty?
      _(" and music they have in common includes: %{artists}") % {
        :artists => Utils.comma_list(artists) }
    else
      nil
    end

    m.reply _("%{a}'s and %{b}'s musical compatibility rating is %{bold}%{r}%{bold}%{common}") % {
      :a => user1,
      :b => user2,
      :r => rating.downcase,
      :bold => Bold,
      :common => common_artists
    }
  end

  def now_playing(m, params)
    opts = { :cache => false }
    user = resolve_username(m, params[:who])
    xml = @bot.httputil.get_response("#{APIURL}method=user.getrecenttracks&user=#{CGI.escape user}", opts)
    doc = Document.new xml.body
    unless doc
      m.reply _("last.fm parsing failed")
      return
    end
    if xml.class == Net::HTTPBadRequest
      if doc.root.elements["error"].attributes["code"] == "6" then
        m.reply _("%{user} doesn't exist on last.fm, perhaps they need to: %{prefix}lastfm set user <username>") % {
          :user => user,
          :prefix => @bot.config['core.address_prefix'].first
        }
        return
      else
        m.reply _("error: %{e}") % {:e => doc.root.element["error"].text}
        return
      end
    end
    now = artist = track = albumtxt = date = nil
    unless doc.root.elements[1].has_elements?
     m.reply _("%{u} hasn't played anything recently") % {:u => user}
     return
    end
    first = doc.root.elements[1].elements[1]
    now = first.attributes["nowplaying"]
    artist = first.elements["artist"].text
    track = first.elements["name"].text
    albumtxt = first.elements["album"].text
    album = if albumtxt
      year = get_album(artist, albumtxt)[2]
      if year
        _(" [%{albumtext}, %{year}]") % { :albumtext => albumtxt, :year => year }
      else
        _(" [%{albumtext}]") % { :albumtext => albumtxt }
      end
    else
      nil
    end
    past = nil
    date = XPath.first(first, "//date")
    if date != nil
      time = date.attributes["uts"]
      past = Time.at(time.to_i)
    end
    if now == "true"
       verb = _("is listening to")
       if @registry.has_key? "#{m.sourcenick}_verb_present"
         verb = @registry["#{m.sourcenick}_verb_present"]
       end
       reply = _("%{u} %{v} \"%{t}\" by %{bold}%{a}%{bold}%{b}") % {:u => user, :v => verb, :t => track, :a => artist, :b => album, :bold => Bold}
    else
      verb = _("listened to")
       if @registry.has_key? "#{m.sourcenick}_verb_past"
         verb = @registry["#{m.sourcenick}_verb_past"]
       end
      ago = Utils.timeago(past)
      reply = _("%{u} %{v} \"%{t}\" by %{bold}%{a}%{bold}%{b} %{p};") % {:u => user, :v => verb, :t => track, :a => artist, :b => album, :p => ago, :bold => Bold}
    end

    if @bot.plugins['spotify'] && Object.const_defined?('Spotify')
      if track = Spotify.search(:track, "#{artist} #{track}")
        reply << _(" [%{u}%{url}%{u}]") % {:u => Underline, :url => track.url}
      end
    end

    reply << _(" -- see %{uri} for more") % { :uri => "http://www.last.fm/user/#{CGI.escape user}"}
    m.reply reply
  end

  def find_artist(m, params)
    info_xml = @bot.httputil.get("#{APIURL}method=artist.getinfo&artist=#{CGI.escape params[:artist].to_s}")
    unless info_xml
      m.reply _("I had problems getting info for %{a}") % {:a => params[:artist]}
      return
    end
    info_doc = Document.new info_xml
    unless info_doc
      m.reply _("last.fm parsing failed")
      return
    end
    tags_xml = @bot.httputil.get("#{APIURL}method=artist.gettoptags&artist=#{CGI.escape params[:artist].to_s}")
    tags_doc = Document.new tags_xml

    first = info_doc.root.elements["artist"]
    artist = first.elements["name"].text
    url = first.elements["url"].text
    stats = {}
    %w(playcount listeners).each do |e|
      t = first.elements["stats/#{e}"].text
      stats[e.to_sym] = t.gsub(/(\d)(?=(\d\d\d)+(?!\d))/, "\\1,")
    end
    summary = first.elements["bio"].elements["summary"].text
    similar = first.get_elements("similar/artist").map { |a|
      _("%{b}%{a}%{b}") % { :a => a.elements["name"].text, :b => Bold } }
    tags = tags_doc.root.get_elements("toptags/tag")[0..4].map { |t|
      _("%{u}%{t}%{u}") % { :t => t.elements["name"].text, :u => Underline } }
    reply = _("%{b}%{a}%{b} <%{u}> has been played %{b}%{c}%{b} times and is being listened to by %{b}%{l}%{b} people") % {
      :b => Bold, :a => artist, :u => url, :c => stats[:playcount], :l => stats[:listeners] }
    reply << _(". Tagged as: %{t}") % {
      :t => tags.join(", "), :b => Bold } unless tags.empty?
    reply << _(". Similar artists: %{s}") % {
      :s => similar.join(", "), :b => Bold } unless similar.empty?
    m.reply reply
    m.reply summary.ircify_html
  end

  def find_track(m, params)
    track = params[:track].to_s
    xml = @bot.httputil.get("#{APIURL}method=track.search&track=#{CGI.escape track}")
    unless xml
      m.reply _("I had problems getting info for %{a}") % {:a => track}
      return
    end
    debug xml
    doc = Document.new xml
    unless doc
      m.reply _("last.fm parsing failed")
      return
    end
    debug doc.root
    results = doc.root.elements["results/opensearch:totalResults"].text.to_i rescue 0
    if results > 0
      begin
        hits = []
        doc.root.each_element("results/trackmatches/track") do |trck|
          hits << _("%{bold}%{t}%{bold} by %{bold}%{a}%{bold} (%{n} listeners)") % {
            :t => trck.elements["name"].text,
            :a => trck.elements["artist"].text,
            :n => trck.elements["listeners"].text,
            :bold => Bold
          }
        end
        m.reply hits.join(' -- '), :split_at => ' -- '
      rescue
        error $!
        m.reply _("last.fm parsing failed")
      end
    else
      m.reply _("track %{a} not found") % {:a => track}
    end
  end

  def find_venue(m, params)
    venue  = params[:venue].to_s
    venues = search_venue_by(:name => venue, :limit => 1)
    venue  = venues.last

    if venues.empty?
      m.reply "sorry, can't find such venue"
      return
    end

    reply = _("%{b}%{name}%{b}, %{street}, %{u}%{city}%{u}, %{country}, see %{url} for more info") % {
      :u => Underline, :b => Bold, :name => venue.name, :city => venue.city, :street => venue.street,
      :country => venue.country, :url => venue.url
    }

    if venue.street && venue.city
      maps_uri = "http://maps.google.com/maps?q=#{venue.street},+#{venue.city}"
      maps_uri << ",+#{venue.postal}" if venue.postal
    elsif venue.lat && venue.long
      maps_uri = "http://maps.google.com/maps?q=#{venue.lat},+#{venue.long}"
    else
      m.reply reply
      return
    end

    maps_uri << "+(#{venue.name.gsub(" ", "%A0")})"

    begin
      require "shorturl"
      maps_uri = ShortURL.shorten(CGI.escape(maps_uri))
    rescue LoadError => e
      error e
    end

    reply << _(" and %{maps} for maps") % { :maps => maps_uri, :b => Bold }
    m.reply reply
  end

  def get_album(artist, album)
    xml = @bot.httputil.get("#{APIURL}method=album.getinfo&artist=#{CGI.escape artist}&album=#{CGI.escape album}")
    unless xml
      return [_("I had problems getting album info")]
    end
    doc = Document.new xml
    unless doc
      return [_("last.fm parsing failed")]
    end
    album = date = playcount = artist = date = year = nil
    first = doc.root.elements["album"]
    artist = first.elements["artist"].text
    playcount = first.elements["playcount"].text
    album = first.elements["name"].text
    date = first.elements["releasedate"].text
    unless date.strip.length < 2
      year = date.strip.split[2].chop
    end
    result = [artist, album, year, playcount]
    return result
  end

  def find_album(m, params)
    album = get_album(params[:artist].to_s, params[:album].to_s)
    if album.length == 1
      m.reply _("I couldn't locate: \"%{a}\" by %{r}") % {:a => params[:album], :r => params[:artist]}
      return
    end
    year = "(#{album[2]}) " unless album[2] == nil
    m.reply _("the album \"%{a}\" by %{r} %{y}has been played %{c} times") % {:a => album[1], :r => album[0], :y => year, :c => album[3]}
  end

  def set_user(m, params)
    user = params[:who].to_s
    nick = m.sourcenick
    @registry[ nick ] = user
    m.reply _("okay, I'll remember that %{n} is %{u} on last.fm") % {:n => nick, :u => user}
  end

  def set_verb(m, params)
    past = params[:past].to_s
    present = params[:present].to_s
    key = "#{m.sourcenick}_verb_"
    @registry[ "#{key}past" ] = past
    @registry[ "#{key}present" ] = present
    m.reply _("okay, I'll remember that %{n} prefers \"%{r}\" and \"%{p}\"") % {:n => m.sourcenick, :p => past, :r => present}
  end

  def get_user(m, params)
    nick = ""
    if params[:who]
      nick = params[:who].to_s
    else
      nick = m.sourcenick
    end
    if @registry.has_key? nick
      user = @registry[ nick ]
      m.reply _("%{nick} is %{user} on last.fm") % {
        :nick => nick,
        :user => user
      }
    else
      m.reply _("sorry, I don't know who %{n} is on last.fm, perhaps they need to: lastfm set user <username>") % {:n => nick}
    end
  end

  def lastfm(m, params)
    action = case params[:action]
    when "neighbors" then "neighbours"
    when "recentracks", "recent" then "recenttracks"
    when "loved" then "lovedtracks"
    when /^weekly(track|album|artist)s$/
      "weekly#{$1}chart"
    when "events"
      find_events(m, params)
      return
    else
      params[:action]
    end.to_sym

    if action == :shouts
      num = params[:num] || @bot.config['lastfm.default_shouts']
      num = num.to_i.clip(1, @bot.config['lastfm.max_shouts'])
    else
      num = params[:num] || @bot.config['lastfm.default_user_data']
      num = num.to_i.clip(1, @bot.config['lastfm.max_user_data'])
    end

    user = resolve_username(m, params[:user])
    uri = "#{APIURL}method=user.get#{action}&user=#{CGI.escape user}"

    if period = params[:period]
      period_uri = (period.last == "year" ? "12month" : period.first + "month")
      uri << "&period=#{period_uri}"
    end

    begin
      res = @bot.httputil.get_response(uri)
      raise _("no response body") unless res.body
    rescue Exception => err
        m.reply _("I had problems accessing last.fm: %{e}") % {:e => err.message}
        return
    end
    doc = Document.new(res.body)
    unless doc
      m.reply _("last.fm parsing failed")
      return
    end

    case res
    when Net::HTTPBadRequest
      if doc.root and doc.root.attributes["status"] == "failed"
        m.reply "error: " << doc.root.elements["error"].text.downcase
      end
      return
    end

    seemore =  _("; see %{uri} for more")
    case action
    when :friends
      friends = doc.root.get_elements("friends/user").map do |u|
        u.elements["name"].text
      end

      if friends.empty?
        reply = _("%{user} has no friends :(")
      elsif friends.length <= num
        reply = _("%{user} has %{total} friends: %{friends}")
      else
        reply = _("%{user} has %{total} friends, including %{friends}%{seemore}")
      end
      m.reply reply % {
        :user => user,
        :total => friends.size,
        :friends => Utils.comma_list(friends.shuffle[0, num]),
        :seemore => seemore % { :uri => "http://www.last.fm/user/#{CGI.escape user}/friends" }
      }
    when :lovedtracks
      loved = doc.root.get_elements("lovedtracks/track").map do |track|
        [track.elements["artist/name"].text, track.elements["name"].text].join(" - ")
      end
      loved_prep = loved.shuffle[0, num].to_enum(:each_with_index).collect { |e,i| (i % 2).zero? ? Underline+e+Underline : e }

      if loved.empty?
        reply = _("%{user} has not loved any tracks")
      elsif loved.length <= num
        reply = _("%{user} has loved %{total} tracks: %{tracks}")
      else
        reply = _("%{user} has loved %{total} tracks, including %{tracks}%{seemore}")
      end

      m.reply reply % {
          :user => user,
          :total => loved.size,
          :tracks => Utils.comma_list(loved_prep),
          :seemore => seemore % { :uri => "http://www.last.fm/user/#{CGI.escape user}/library/loved" }
        }
    when :neighbours
      nbrs = doc.root.get_elements("neighbours/user").map do |u|
        u.elements["name"].text
      end

      if nbrs.empty?
        reply = _("no one seems to share %{user}'s musical taste")
      elsif nbrs.length <= num
        reply = _("%{user}'s musical neighbours are %{nbrs}")
      else
        reply = _("%{user}'s musical neighbours include %{nbrs}%{seemore}")
      end
      m.reply reply % {
          :user    => user,
          :nbrs    => Utils.comma_list(nbrs.shuffle[0, num]),
          :seemore => seemore % { :uri => "http://www.last.fm/user/#{CGI.escape user}/neighbours" }
      }
    when :recenttracks
      tracks = doc.root.get_elements("recenttracks/track").map do |track|
        [track.elements["artist"].text, track.elements["name"].text].join(" - ")
      end

      counts = []
      tracks.each do |track|
        if t = counts.assoc(track)
          counts[counts.rindex(t)] = [track, t[-1] += 1]
        else
          counts << [track, 1]
        end
      end

      tracks_prep = counts[0, num].to_enum(:each_with_index).map do |e,i|
        str = (i % 2).zero? ? Underline+e[0]+Underline : e[0]
        str << " (%{i} times%{m})" % {
          :i => e.last,
          :m => counts.size == 1 ? _(" or more") : nil
        } if e.last > 1
        str
      end

      if tracks.empty?
        m.reply _("%{user} hasn't played anything recently") % { :user => user }
      else
        m.reply _("%{user} has recently played %{tracks}") %
          { :user => user, :tracks => Utils.comma_list(tracks_prep) }
      end
    when :shouts
      shouts = doc.root.get_elements("shouts/shout")
      if shouts.empty?
        m.reply _("there are no shouts for %{user}") % { :user => user }
      else
        shouts[0, num].each do |shout|
          m.reply _("<%{author}> %{body}") % {
            :body   => shout.elements["body"].text,
            :author => shout.elements["author"].text,
          }
        end
      end
    when :toptracks, :topalbums, :topartists, :weeklytrackchart, :weeklyalbumchart, :weeklyartistchart
      type  = action.to_s.scan(/track|album|artist/).to_s
      items = doc.root.get_elements("#{action}/#{type}").map do |item|
        case action
        when :weeklytrackchart, :weeklyalbumchart
          format = "%{artist} - %{title} (%{bold}%{plays}%{bold})"
          artist = item.elements["artist"].text
        when :weeklyartistchart, :topartists
          format = "%{artist} (%{bold}%{plays}%{bold})"
          artist = item.elements["name"].text
        when :toptracks, :topalbums
          format = "%{artist} - %{title} (%{bold}%{plays}%{bold})"
          artist = item.elements["artist/name"].text
        end

        _(format) % {
          :artist => artist,
          :title  => item.elements["name"].text,
          :plays  => item.elements["playcount"].text,
          :bold   => Bold
        }
      end
      if items.empty?
        m.reply _("%{user} hasn't played anything in this period of time") % { :user => user }
      else
        m.reply items[0, num].join(", ")
      end
    end
  end

  def resolve_username(m, name)
    name = m.sourcenick if name.nil?
    @registry[name] or name
  end
end

event_map_options = {
 :action => :find_events,
 :requirements => {
  :num => /\d+/,
  :sort_order => /(?:asc|desc)(?:ending)?/
 },
 :thread => true
}

plugin = LastFmPlugin.new
plugin.map 'lastfm [:num] event[s] in *location [sort[ed] by :sort_by] [[in] :sort_order [order]]', event_map_options.dup
plugin.map 'lastfm [:num] event[s] by *who [sort[ed] by :sort_by] [[in] :sort_order [order]]', event_map_options.dup
plugin.map 'lastfm [:num] event[s] at *venue [sort[ed] by :sort_by] [[in] :sort_order [order]]', event_map_options.dup
plugin.map 'lastfm [:num] event[s] [for] *who [sort[ed] by :sort_by] [[in] :sort_order [order]]', event_map_options.dup
plugin.map 'lastfm artist *artist', :action => :find_artist, :thread => true
plugin.map 'lastfm album *album [by *artist]', :action => :find_album
plugin.map 'lastfm track *track', :action => :find_track, :thread => true
plugin.map 'lastfm venue *venue', :action => :find_venue, :thread => true
plugin.map 'lastfm set user[name] :who', :action => :set_user, :thread => true
plugin.map 'lastfm set verb *present, *past', :action => :set_verb, :thread => true
plugin.map 'lastfm who [:who]', :action => :get_user, :thread => true
plugin.map 'lastfm compare to :user2', :action => :tasteometer, :thread => true
plugin.map 'lastfm compare [:user1] [to] :user2', :action => :tasteometer, :thread => true
plugin.map "lastfm [user] [:num] :action [:user]", :thread => true,
  :requirements => {
    :action => /^(?:events|shouts|friends|neighbou?rs|loved(?:tracks)?|recent(?:t?racks)?|top(?:album|artist|track)s?|weekly(?:albums?|artists?|tracks?)(?:chart)?)$/,
    :num => /^\d+$/
}
plugin.map 'lastfm [user] [:num] :action [:user] over [*period]', :thread => true,
  :requirements => {
    :action => /^(?:top(?:album|artist|track)s?)$/,
    :period => /^(?:(?:3|6|12) months)|(?:a\s|1\s)?year$/,
    :num => /^\d+$/
}
plugin.map 'lastfm [now] [:who]', :action => :now_playing, :thread => true
plugin.map 'np [:who]', :action => :now_playing, :thread => true
