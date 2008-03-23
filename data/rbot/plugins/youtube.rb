#-- vim:sw=2:et
#++
#
# :title: YouTube plugin for rbot
#
# Author:: Giuseppe "Oblomov" Bilotta <giuseppe.bilotta@gmail.com>
#
# Copyright:: (C) 2008 Giuseppe Bilotta


class YouTubePlugin < Plugin
  YOUTUBE_SEARCH = "http://gdata.youtube.com/feeds/api/videos?vq=%{words}&orderby=relevance"
  YOUTUBE_VIDEO = "http://gdata.youtube.com/feeds/api/videos/%{code}"

  Config.register Config::IntegerValue.new('youtube.hits',
    :default => 3,
    :desc => "Number of hits to return from YouTube searches")
  Config.register Config::IntegerValue.new('youtube.descs',
    :default => 3,
    :desc => "When set to n > 0, the bot will return the description of the first n videos found")

  def youtube_filter(s)
    loc = Utils.check_location(s, /youtube\.com/)
    return nil unless loc
    if s[:text].include? '<div id="vidTitle">'
      video_info = @bot.filter(:"youtube.video", s)
      return nil # TODO
    elsif s[:text].include? '<!-- start search results -->'
      vids = @bot.filter(:"youtube.search", s)[:videos]
      if !vids.empty?
        return nil # TODO
      end
    end
    # otherwise, just grab the proper div
    if defined? Hpricot
      content = (Hpricot(s[:text])/"#mainContent").to_html.ircify_html
    end
    # suboptimal, but still better than the default HTML info extractor
    content ||= /<div id="mainContent"[^>]*>/.match(s[:text]).post_match.ircify_html
    return {:title => s[:text].ircify_html_title, :content => content}
  end

  def youtube_apivideo_filter(s)
    # This filter can be used either
    e = s[:rexml] || REXML::Document.new(s[:text]).elements["entry"]
    # TODO precomputing mg doesn't work on my REXML, despite what the doc
    # says?
    #   mg = e.elements["media:group"]
    #   :title => mg["media:title"].text
    # fails because "media:title" is not an Integer. Bah
    vid = {
      :author => (e.elements["author/name"].text rescue nil),
      :title =>  (e.elements["media:group/media:title"].text rescue nil),
      :desc =>   (e.elements["media:group/media:description"].text rescue nil),
      :cat => (e.elements["media:group/media:category"].text rescue nil),
      :seconds => (e.elements["media:group/yt:duration/@seconds"].value.to_i rescue nil),
      :url => (e.elements["media:group/media:player/@url"].value rescue nil),
      :rating => (("%s/%s" % [e.elements["gd:rating/@average"].value, e.elements["gd:rating/@max"].value]) rescue nil),
      :views => (e.elements["yt:statistics/@viewCount"].value rescue nil),
      :faves => (e.elements["yt:statistics/@favoriteCount"].value rescue nil)
    }
    if vid[:desc]
      vid[:desc].gsub!(/\s+/m, " ")
    end
    if secs = vid[:seconds]
      mins, secs = secs.divmod 60
      hours, mins = mins.divmod 60
      if hours > 0
        vid[:duration] = "%s:%s:%s" % [hours, mins, secs]
      elsif mins > 0
        vid[:duration] = "%s'%s\"" % [mins, secs]
      else
        vid[:duration] = "%ss" % [secs]
      end
    else
      vid[:duration] = _("unknown duration")
    end
    debug vid
    return vid
  end

  def youtube_apisearch_filter(s)
    vids = []
    title = nil
    begin
      doc = REXML::Document.new(s[:text])
      title = doc.elements["feed/title"].text
      doc.elements.each("*/entry") { |e|
        vids << @bot.filter(:"youtube.apivideo", :rexml => e)
      }
      debug vids
    rescue => e
      debug e
    end
    return {:title => title, :vids => vids}
  end

  def youtube_search_filter(s)
    # TODO
    # hits = s[:hits] || @bot.config['youtube.hits']
    # scrap the videos
    return []
  end

  def youtube_video_filter(s)
    # TODO
  end

  def initialize
    super
    @bot.register_filter(:youtube, :htmlinfo) { |s| youtube_filter(s) }
    @bot.register_filter(:apisearch, :youtube) { |s| youtube_apisearch_filter(s) }
    @bot.register_filter(:apivideo, :youtube) { |s| youtube_apivideo_filter(s) }
    @bot.register_filter(:search, :youtube) { |s| youtube_search_filter(s) }
    @bot.register_filter(:video, :youtube) { |s| youtube_video_filter(s) }
  end

  def info(m, params)
    movie = params[:movie]
    code = ""
    case movie
    when %r{youtube.com/watch\?v=(.*?)(&.*)?$}
      code = $1.dup
    when %r{youtube.com/v/(.*)$}
      code = $1.dup
    when /^[A-Za-z0-9]+$/
      code = movie.dup
    end
    if code.empty?
      m.reply _("What movie was that, again?")
      return
    end

    url = YOUTUBE_VIDEO % {:code => code}
    resp, xml = @bot.httputil.get_response(url)
    unless Net::HTTPSuccess === resp
      m.reply(_("error looking for movie %{code} on youtube: %{e}") % {:code => code, :e => xml})
      return
    end
    debug "filtering XML"
    debug xml
    begin
      vid = @bot.filter(:"youtube.apivideo", DataStream.new(xml, params))
    rescue => e
      debug e
    end
    if vid
      m.reply(_("%{bold}%{title}%{bold} [%{cat}] %{rating} @ %{url} by %{author} (%{duration}). %{views} views, faved %{faves} times. %{desc}") %
              {:bold => Bold}.merge(vid))
    else
      m.reply(_("couldn't retrieve infos on video code %{code}") % {:code => code})
    end
  end

  def search(m, params)
    what = params[:words].to_s
    searchfor = CGI.escape what
    url = YOUTUBE_SEARCH % {:words => searchfor}
    resp, xml = @bot.httputil.get_response(url)
    unless Net::HTTPSuccess === resp
      m.reply(_("error looking for %{what} on youtube: %{e}") % {:what => what, :e => xml})
      return
    end
    debug "filtering XML"
    vids = @bot.filter(:"youtube.apisearch", DataStream.new(xml, params))[:vids][0, @bot.config['youtube.hits']]
    debug vids
    case vids.length
    when 0
      m.reply _("no videos found for %{what}") % {:what => what}
      return
    when 1
      show = "%{title} (%{duration}) [%{desc}] @ %{url}" % vids.first
      m.reply _("One video found for %{what}: %{show}") % {:what => what, :show => show}
    else
      idx = 0
      shorts = vids.inject([]) { |list, el|
        idx += 1
        list << ("#{idx}. %{bold}%{title}%{bold} (%{duration}) @ %{url}" % {:bold => Bold}.merge(el))
      }.join(" | ")
      m.reply(_("Videos for %{what}: %{shorts}") % {:what =>what, :shorts => shorts},
              :split_at => /\s+\|\s+/)
      if (descs = @bot.config['youtube.descs']) > 0
        vids[0, descs].each_with_index { |v, i|
          m.reply("[#{i+1}] %{title} (%{duration}): %{desc}" % v, :overlong => :truncate)
        }
      end
    end
  end

end

plugin = YouTubePlugin.new

plugin.map "youtube info :movie", :action => 'info', :threaded => true
plugin.map "youtube [search] *words", :action => 'search', :threaded => true
