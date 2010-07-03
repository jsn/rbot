#-- vim:sw=2:et
#++
#
# :title: Freshmeat plugin for rbot

require 'rexml/document'

class FreshmeatPlugin < Plugin
  include REXML

  Config.register Config::StringValue.new('freshmeat.api_token',
    :desc => "Auth token for freshmeat API requests. Without this, no freshmeat calls will be made. Find it in your freshmeat user account settings.",
    :default => "")

  def api_token
    return @bot.config['freshmeat.api_token']
  end

  # Checks if an API token is configure, warns if not, returns true or false
  def check_api_token(m=nil)
    if api_token.empty?
      if m
        m.reply _("you must set the configuration value freshmeat.api_token to a valid freshmeat auth token, otherwise I cannot make requests to the site")
      end
      return false
    end
    return true
  end

  def help(plugin, topic="")
    "freshmeat search [<max>=4] <string> => search freshmeat for <string>, freshmeat [<max>=4] => return up to <max> freshmeat headlines"
  end

  REL_ENTRY = %r{<a href="/(release)s/(\d+)/"><font color="#000000">(.*?)</font></a>}
  PRJ_ENTRY = %r{<a href="/(project)s/(\S+?)/"><b>(.*?)</b></a>}

  # This method defines a filter for fm pages. It's needed because the generic
  # summarization grabs a comment, not the actual article.
  #
  def freshmeat_filter(s)
    loc = Utils.check_location(s, /freshmeat\.net/)
    return nil unless loc
    entries = []
    s[:text].scan(/#{REL_ENTRY}|#{PRJ_ENTRY}/) { |m|
      entry = {
        :type => ($1 || $4).dup,
        :code => ($2 || $5).dup,
        :name => ($3 || $6).dup
      }
      entries << entry
    }
    return nil if entries.empty?
    title = s[:text].ircify_html_title
    content = entries.inject([]) { |l, e| l << e[:name] }.join(" | ")
    return {:title => title, :content => content}
  end

  def initialize
    super
    @bot.register_filter(:freshmeat, :htmlinfo) { |s| freshmeat_filter(s) }
  end

  def search_freshmeat(m, params)
    return unless check_api_token(m)
    max = params[:limit].to_i
    search = params[:search].to_s
    max = 8 if max > 8
    xml = @bot.httputil.get("http://freshmeat.net/search.xml?auth_code=#{api_token}&q=#{CGI.escape(search)}")
    unless xml
      m.reply "search for #{search} failed (is the API token configured correctly?)"
      return
    end
    doc = nil
    begin
      doc = Document.new xml
    rescue
      debug xml
      error $!
    end
    unless doc
      m.reply "search for #{search} failed"
      return
    end
    matches = Array.new
    max_width = 250
    title_width = 0
    url_width = 0
    done = 0
    doc.elements.each("hash/projects/project") {|e|
      title = e.elements["name"].text
      title_width = title.length if title.length > title_width

      url = "http://freshmeat.net/projects/#{e.elements['permalink'].text}"
      url_width = url.length if url.length > url_width

      desc = e.elements["oneliner"].text

      matches << [title, url, desc]
      done += 1
      break if done >= max
    }
    if matches.length == 0
      m.reply "not found: #{search}"
    end

    title_width += 2 # for bold

    matches.each {|mat|
      title = Bold + mat[0] + Bold
      url = mat[1]
      desc = mat[2]
      reply = sprintf("%s | %s | %s", title.ljust(title_width), url.ljust(url_width), desc)
      m.reply reply, :overlong => :truncate
    }
  end

  # We do manual parsing so that we can work even with the RSS plugin not loaded
  def freshmeat_rss(m, params)
    max = params[:limit].to_i
    max = 8 if max > 8

    text = _("retrieving freshmeat news from the RSS")
    reason = ""
    case params[:api_token]
    when :missing
      reason = _(" because no API token is configured")
    when :wrong
      reason = _(" because the configured API token is wrong")
    end

    m.reply text + reason

    begin
      xml = @bot.httputil.get('http://freshmeat.net/?format=atom')
      unless xml
        m.reply _("couldn't retrieve freshmeat news feed")
        return
      end
      doc = Document.new xml
      unless doc
        m.reply "freshmeat news parse failed"
        return
      end
    rescue
      error $!
      m.reply "freshmeat news parse failed"
      return
    end

    matches = Array.new
    max_width = 60
    title_width = 0
    done = 0
    doc.elements.each("feed/entry") {|e|
      # TODO desc should be replaced by the oneliner, but this means one more hit per project
      # so we clip out all of the description and leave just the 'changes' part
      desc = e.elements["content"].text.ircify_html.sub(/.*?#{Bold}Changes:#{Bold}/,'').strip
      title = e.elements["title"].text.ircify_html.strip
      title_width = title.length if title.length > title_width
      matches << [title, desc]
      done += 1
      break if done >= max
    }
    title_width += 2
    matches.each {|mat|
      title = Bold + mat[0] + Bold
      desc = mat[1]
      reply = sprintf("%s | %s", title.ljust(title_width), desc)
      m.reply reply, :overlong => :truncate
    }
  end

  def freshmeat(m, params)
    # use the RSS if no API token is defined
    return freshmeat_rss(m, params.merge(:api_token => :missing)) unless check_api_token
    xml = @bot.httputil.get("http://freshmeat.net/index.xml?auth_code=#{api_token}")
    # use the RSS if we couldn't get the XML
    return freshmeat_rss(m, params.merge(:api_token => :wrong)) unless xml

    max = params[:limit].to_i
    max = 8 if max > 8
    begin
      doc = Document.new xml
      unless doc
        m.reply "freshmeat news parse failed"
        return
      end
    rescue
      error $!
      m.reply "freshmeat news parse failed"
      return
    end

    matches = Array.new
    title_width = 0
    url_width = 0
    time_width = 0
    done = 0
    now = Time.now
    doc.elements.each("releases/release") {|e|
      approved = e.elements["approved-at"].text.strip
      date = Time.parse(approved) rescue nil
      timeago = date ? (Utils.timeago(date, :start_date => now) rescue nil) : approved
      time_width = timeago.length if timeago.length > time_width

      changelog = e.elements["changelog"].text.ircify_html

      title = e.elements["project/name"].text.ircify_html
      title_width = title.length if title.length > title_width
      url = "http://freshmeat.net/projects/#{e.elements['project/permalink'].text}"
      url_width = url.length if url.length > url_width

      desc = e.elements["project/oneliner"].text.ircify_html

      matches << [title, timeago, desc, url, changelog]

      done += 1
      break if done >= max
    }

    if matches.empty?
      m.reply _("no news in freshmeat!")
      return
    end

    title_width += 2
    matches.each {|mat|
      title = Bold + mat[0] + Bold
      timeago = mat[1]
      desc = mat[2]
      url = mat[3]
      changelog = mat[4]
      reply = sprintf("%s | %s | %s | %s",
        timeago.rjust(time_width),
        title.ljust(title_width),
        url.ljust(url_width),
        desc)
      m.reply reply, :overlong => :truncate
    }
  end
end
plugin = FreshmeatPlugin.new
plugin.map 'freshmeat search :limit *search', :action => 'search_freshmeat',
            :defaults => {:limit => 4}, :requirements => {:limit => /^\d+$/}
plugin.map 'freshmeat :limit', :defaults => {:limit => 4},
                               :requirements => {:limit => /^\d+$/}
