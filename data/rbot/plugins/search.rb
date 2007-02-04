require 'uri'

Net::HTTP.version_1_2

GOOGLE_WAP_LINK = /<a accesskey="(\d)" href=".*?u=(.*?)">(.*?)<\/a>/im

class ::String
  def omissis_after(len)
    if self.length > len
      return self[0...len].sub(/\s+\S*$/,"...")
    else
      return self
    end
  end

  def ircify_html
    txt = self

    # bold and strong -> bold
    txt.gsub!(/<\/?(?:b|strong)\s*>/, "#{Bold}")

    # italic, emphasis and underline -> underline
    txt.gsub!(/<\/?(?:i|em|u)\s*>/, "#{Underline}")

    ## This would be a nice addition, but the results are horrible
    ## Maybe make it configurable?
    # txt.gsub!(/<\/?a( [^>]*)?>/, "#{Reverse}")

    # Paragraph and br tags are converted to whitespace.
    txt.gsub!(/<\/?(p|br)\s*\/?\s*>/, ' ')
    txt.gsub!("\n", ' ')

    # All other tags are just removed
    txt.gsub!(/<[^>]+>/, '')

    # Remove double formatting options, since they only waste bytes
    txt.gsub!(/#{Bold}\s*#{Bold}/,"")
    txt.gsub!(/#{Underline}\s*#{Underline}/,"")

    # And finally whitespace is squeezed
    txt.gsub!(/\s+/, ' ')

    # Decode entities and strip whitespace
    return Utils.decode_html_entities(txt).strip!
  end
end

class SearchPlugin < Plugin
  BotConfig.register BotConfigIntegerValue.new('google.hits',
    :default => 3,
    :desc => "Number of hits to return from Google searches")
  BotConfig.register BotConfigIntegerValue.new('google.first_par',
    :default => 0,
    :desc => "When set to n > 0, the bot will return the first paragraph from the first n search hits")
  BotConfig.register BotConfigIntegerValue.new('wikipedia.hits',
    :default => 3,
    :desc => "Number of hits to return from Wikipedia searches")
  BotConfig.register BotConfigIntegerValue.new('wikipedia.first_par',
    :default => 1,
    :desc => "When set to n > 0, the bot will return the first paragraph from the first n wikipedia search hits")

  def help(plugin, topic="")
    case topic
    when "search", "google"
      "#{topic} <string> => search google for <string>"
    when "wp"
      "wp [<code>] <string> => search for <string> on Wikipedia. You can select a national <code> to only search the national Wikipedia"
    else
      "search <string> (or: google <string>) => search google for <string> | wp <string> => search for <string> on Wikipedia"
    end
  end

  def google(m, params)
    what = params[:words].to_s
    searchfor = URI.escape what
    # This method is also called by other methods to restrict searching to some sites
    if params[:site]
      site = "site:#{params[:site]}+"
    else
      site = ""
    end
    # It is also possible to choose a filter to remove constant parts from the titles
    # e.g.: "Wikipedia, the free encyclopedia" when doing Wikipedia searches
    filter = params[:filter] || ""

    url = "http://www.google.com/wml/search?q=#{site}#{searchfor}"

    hits = params[:hits] || @bot.config['google.hits']

    begin
      wml = @bot.httputil.get_cached(url)
    rescue => e
      m.reply "error googling for #{what}"
      return
    end
    results = wml.scan(GOOGLE_WAP_LINK)
    if results.length == 0
      m.reply "no results found for #{what}"
      return
    end
    urls = Array.new
    results = results[0...hits].map { |res|
      n = res[0]
      t = Utils.decode_html_entities res[2].gsub(filter, '').strip
      u = URI.unescape res[1]
      urls.push(u)
      "#{n}. #{Bold}#{t}#{Bold}: #{u}"
    }.join(" | ")

    m.reply "Results for #{what}: #{results}"

    first_pars = params[:firstpar] || @bot.config['google.first_par']

    idx = 0
    while first_pars > 0 and urls.length > 0
      url.replace(urls.shift)
      idx += 1
      xml = @bot.httputil.get_cached(url)
      if xml.nil?
        debug "Unable to retrieve #{url}"
        next
      end
      # We get the first par after the first main heading, if possible
      header_found = xml.match(/<h1(?:\s+[^>]*)?>(.*?)<\/h1>/im)
      txt = String.new
      if header_found
        debug "Found header: #{header_found[1].inspect}"
        while txt.empty? 
          header_found = $'
          candidate = header_found[/<p(?:\s+[^>]*)?>.*?<\/p>/im].ircify_html
          break unless candidate
          txt.replace candidate
        end
      end
      # If we haven't found a first par yet, try to get it from the whole
      # document
      if txt.empty?
        txt = xml[/<p(?:\s+[^>]*)?>.*?<\/p>/im].ircify_html
        while txt.empty? 
          header_found = $'
          candidate = header_found[/<p(?:\s+[^>]*)?>.*?<\/p>/im].ircify_html
          break unless candidate
          txt.replace candidate
        end
      end
      # Nothing yet, give up
      if txt.empty?
        debug "No first par found\n#{xml}"
        next
      end
      m.reply "[#{idx}] #{txt}".omissis_after(400)
      first_pars -=1
    end
  end

  def wikipedia(m, params)
    lang = params[:lang]
    site = "#{lang.nil? ? '' : lang + '.'}wikipedia.org"
    debug "Looking up things on #{site}"
    params[:site] = site
    params[:filter] = / - Wikipedia.*$/
    params[:hits] = @bot.config['wikipedia.hits']
    params[:firstpar] = @bot.config['wikipedia.first_par']
    return google(m, params)
  end
end

plugin = SearchPlugin.new

plugin.map "search *words", :action => 'google'
plugin.map "google *words", :action => 'google'
plugin.map "wp :lang *words", :action => 'wikipedia', :requirements => { :lang => /^\w\w\w?$/ }
plugin.map "wp *words", :action => 'wikipedia'

