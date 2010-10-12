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
  YOUTUBE_VIDEO = "http://gdata.youtube.com/feeds/api/videos/%{id}"

  YOUTUBE_VIDEO_URLS = %r{youtube.com/(?:watch\?v=|v/)(.*?)(&.*)?$}

  Config.register Config::IntegerValue.new('youtube.hits',
    :default => 3,
    :desc => "Number of hits to return from YouTube searches")
  Config.register Config::IntegerValue.new('youtube.descs',
    :default => 3,
    :desc => "When set to n > 0, the bot will return the description of the first n videos found")
  Config.register Config::BooleanValue.new('youtube.formats',
    :default => true,
    :desc => "Should the bot display alternative URLs (swf, rstp) for YouTube videos?")

  def youtube_filter(s)
    loc = Utils.check_location(s, /youtube\.com/)
    return nil unless loc
    if s[:text].include? '<link rel="alternate" type="text/xml+oembed"'
      vid = @bot.filter(:"youtube.video", s)
      return nil unless vid
      content = _("Category: %{cat}. Rating: %{rating}. Author: %{author}. Duration: %{duration}. %{views} views, faved %{faves} times. %{desc}") % vid
      return vid.merge(:content => content)
    elsif s[:text].include? '<!-- start search results -->'
      vids = @bot.filter(:"youtube.search", s)[:videos]
      if !vids.empty?
        return nil # TODO
      end
    end
    # otherwise, just grab the proper div
    if defined? Hpricot
      content = (Hpricot(s[:text])/".watch-video-desc").to_html.ircify_html
    end
    # suboptimal, but still better than the default HTML info extractor
    dm = /<div\s+class="watch-video-desc"[^>]*>/.match(s[:text])
    content ||= dm ? dm.post_match.ircify_html : '(no description found)'
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
      :formats => [],
      :author => (e.elements["author/name"].text rescue nil),
      :title =>  (e.elements["media:group/media:title"].text rescue nil),
      :desc =>   (e.elements["media:group/media:description"].text rescue nil),
      :cat => (e.elements["media:group/media:category"].text rescue nil),
      :seconds => (e.elements["media:group/yt:duration/"].attributes["seconds"].to_i rescue nil),
      :url => (e.elements["media:group/media:player/"].attributes["url"] rescue nil),
      :rating => (("%s/%s" % [e.elements["gd:rating"].attributes["average"], e.elements["gd:rating/@max"].value]) rescue nil),
      :views => (e.elements["yt:statistics"].attributes["viewCount"] rescue nil),
      :faves => (e.elements["yt:statistics"].attributes["favoriteCount"] rescue nil)
    }
    if vid[:desc]
      vid[:desc].gsub!(/\s+/m, " ")
    end
    if secs = vid[:seconds]
      vid[:duration] = Utils.secs_to_short(secs)
    else
      vid[:duration] = _("unknown duration")
    end
    e.elements.each("media:group/media:content") { |c|
      if url = (c.attributes["url"] rescue nil)
        type = c.attributes["type"] rescue nil
        medium = c.attributes["medium"] rescue nil
        expression = c.attributes["expression"] rescue nil
        seconds = c.attributes["duration"].to_i rescue nil
        fmt = case num_fmt = (c.attributes["yt:format"] rescue nil)
              when "1"
                "h263+amr"
              when "5"
                "swf"
              when "6"
                "mp4+aac"
              when nil
                nil
              else
                num_fmt
              end
        vid[:formats] << {
          :url => url, :type => type,
          :medium => medium, :expression => expression,
          :seconds => seconds,
          :numeric_format => num_fmt,
          :format => fmt
        }.delete_if { |k, v| v.nil? }
        if seconds
          vid[:formats].last[:duration] = Utils.secs_to_short(seconds)
        else
          vid[:formats].last[:duration] = _("unknown duration")
        end
      end
    }
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

  # Filter a YouTube video URL
  def youtube_video_filter(s)
    id = s[:youtube_video_id]
    if not id
      url = s.key?(:headers) ? s[:headers]['x-rbot-location'].first : s[:url]
      debug url
      id = YOUTUBE_VIDEO_URLS.match(url).captures.first rescue nil
    end
    return nil unless id

    debug id

    url = YOUTUBE_VIDEO % {:id => id}
    resp, xml = @bot.httputil.get_response(url)
    unless Net::HTTPSuccess === resp
      debug("error looking for movie %{id} on youtube: %{e}" % {:id => id, :e => xml})
      return nil
    end
    debug xml
    begin
      return @bot.filter(:"youtube.apivideo", DataStream.new(xml, s))
    rescue => e
      debug e
      return nil
    end
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
    id = nil
    if movie =~ /^[A-Za-z0-9]+$/
      id = movie.dup
    end

    vid = @bot.filter(:"youtube.video", :url => movie, :youtube_video_id => id)
    if vid
      str = _("%{bold}%{title}%{bold} [%{cat}] %{rating} @ %{url} by %{author} (%{duration}). %{views} views, faved %{faves} times. %{desc}") %
        {:bold => Bold}.merge(vid)
      if @bot.config['youtube.formats'] and not vid[:formats].empty?
        str << _("\n -- also available at: ")
        str << vid[:formats].inject([]) { |list, fmt|
          list << ("%{url} %{type} %{format} (%{duration} %{expression} %{medium})" % fmt)
        }.join(', ')
      end
      m.reply str
    else
      m.reply(_("couldn't retrieve video info") % {:id => id})
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
