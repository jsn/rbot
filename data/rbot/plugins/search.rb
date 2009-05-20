#-- vim:sw=2:et
#++
#
# :title: Google and Wikipedia search plugin for rbot
#
# Author:: Tom Gilbert (giblet) <tom@linuxbrit.co.uk>
# Author:: Giuseppe "Oblomov" Bilotta <giuseppe.bilotta@gmail.com>
#
# Copyright:: (C) 2002-2005 Tom Gilbert
# Copyright:: (C) 2006 Tom Gilbert, Giuseppe Bilotta
# Copyright:: (C) 2006-2007 Giuseppe Bilotta

# TODO:: use lr=lang_<code> or whatever is most appropriate to let google know
#        it shouldn't use the bot's location to find the preferred language
# TODO:: support localized uncyclopedias -- not easy because they have different names
#        for most languages

GOOGLE_SEARCH = "http://www.google.com/search?oe=UTF-8&q="
GOOGLE_WAP_SEARCH = "http://www.google.com/wml/search?hl=en&q="
GOOGLE_WAP_LINK = /<a accesskey="(\d)" href=".*?u=(.*?)">(.*?)<\/a>/im
GOOGLE_CALC_RESULT = %r{<img src=/images/calc_img\.gif(?: width=40 height=30 alt="")?>.*?<h2 class=r[^>]*><b>(.+?)</b>}
GOOGLE_COUNT_RESULT = %r{<font size=-1>Results <b>1<\/b> - <b>10<\/b> of about <b>(.*)<\/b> for}
GOOGLE_DEF_RESULT = %r{<p> (Web definitions for .*?)<br/>(.*?)<br/>(.*?)\s-\s+<a href}
GOOGLE_TIME_RESULT = %r{alt="Clock"></td><td valign=[^>]+>(.+?)<(br|/td)>}

class SearchPlugin < Plugin
  Config.register Config::IntegerValue.new('google.hits',
    :default => 3,
    :desc => "Number of hits to return from Google searches")
  Config.register Config::IntegerValue.new('google.first_par',
    :default => 0,
    :desc => "When set to n > 0, the bot will return the first paragraph from the first n search hits")
  Config.register Config::IntegerValue.new('wikipedia.hits',
    :default => 3,
    :desc => "Number of hits to return from Wikipedia searches")
  Config.register Config::IntegerValue.new('wikipedia.first_par',
    :default => 1,
    :desc => "When set to n > 0, the bot will return the first paragraph from the first n wikipedia search hits")

  def help(plugin, topic="")
    case topic
    when "search", "google"
      "#{topic} <string> => search google for <string>"
    when "gcalc"
      "gcalc <equation> => use the google calculator to find the answer to <equation>"
    when "gdef"
      "gdef <term(s)> => use the google define mechanism to find a definition of <term(s)>"
    when "gtime"
      "gtime <location> => use the google clock to find the current time at <location>"
    when "wp"
      "wp [<code>] <string> => search for <string> on Wikipedia. You can select a national <code> to only search the national Wikipedia"
    when "unpedia"
      "unpedia <string> => search for <string> on Uncyclopedia"
    else
      "search <string> (or: google <string>) => search google for <string> | wp <string> => search for <string> on Wikipedia | unpedia <string> => search for <string> on Uncyclopedia"
    end
  end

  def google(m, params)
    what = params[:words].to_s
    searchfor = CGI.escape what
    # This method is also called by other methods to restrict searching to some sites
    if params[:site]
      site = "site:#{params[:site]}+"
    else
      site = ""
    end
    # It is also possible to choose a filter to remove constant parts from the titles
    # e.g.: "Wikipedia, the free encyclopedia" when doing Wikipedia searches
    filter = params[:filter] || ""

    url = GOOGLE_WAP_SEARCH + site + searchfor

    hits = params[:hits] || @bot.config['google.hits']

    first_pars = params[:firstpar] || @bot.config['google.first_par']

    single = (hits == 1 and first_pars == 1)

    begin
      wml = @bot.httputil.get(url)
      raise unless wml
    rescue => e
      m.reply "error googling for #{what}"
      return
    end
    results = wml.scan(GOOGLE_WAP_LINK)
    if results.length == 0
      m.reply "no results found for #{what}"
      return
    end
    single ||= (results.length==1)
    urls = Array.new
    results = results[0...hits].map { |res|
      n = res[0]
      t = Utils.decode_html_entities res[2].gsub(filter, '').strip
      u = URI.unescape res[1]
      urls.push(u)
      single ? u : "#{n}. #{Bold}#{t}#{Bold}: #{u}"
    }.join(" | ")

    if params[:lucky]
      m.reply urls.first
      return
    end

    # If we return a single, full result, change the output to a more compact representation
    if single
      m.reply "Result for %s: %s -- %s" % [what, results, Utils.get_first_pars(urls, first_pars)], :overlong => :truncate
      return
    end

    m.reply "Results for #{what}: #{results}", :split_at => /\s+\|\s+/

    return unless first_pars > 0

    Utils.get_first_pars urls, first_pars, :message => m

  end

  def lucky(m, params)
    params.merge!(:lucky => true)
    google(m, params)
  end

  def gcalc(m, params)
    what = params[:words].to_s
    searchfor = CGI.escape(what)

    debug "Getting gcalc thing: #{searchfor.inspect}"
    url = GOOGLE_SEARCH + searchfor

    begin
      html = @bot.httputil.get(url)
    rescue => e
      m.reply "error googlecalcing #{what}"
      return
    end

    debug "#{html.size} bytes of html recieved"

    results = html.scan(GOOGLE_CALC_RESULT)
    debug "results: #{results.inspect}"

    if results.length != 1
      m.reply "couldn't calculate #{what}"
      return
    end

    result = results[0][0].ircify_html
    debug "replying with: #{result.inspect}"
    m.reply "#{result}"
  end

  def gcount(m, params)
    what = params[:words].to_s
    searchfor = CGI.escape(what)

    debug "Getting gcount thing: #{searchfor.inspect}"
    url = GOOGLE_SEARCH + searchfor

    begin
      html = @bot.httputil.get(url)
    rescue => e
      m.reply "error googlecounting #{what}"
      return
    end

    debug "#{html.size} bytes of html recieved"

    results = html.scan(GOOGLE_COUNT_RESULT)
    debug "results: #{results.inspect}"

    if results.length != 1
      m.reply "couldn't count #{what}"
      return
    end

    result = results[0][0].ircify_html
    debug "replying with: #{result.inspect}"
    m.reply "total results: #{result}"

  end

  def gdef(m, params)
    what = params[:words].to_s
    searchfor = CGI.escape("define " + what)

    debug "Getting gdef thing: #{searchfor.inspect}"
    url = GOOGLE_WAP_SEARCH + searchfor

    begin
      html = @bot.httputil.get(url)
    rescue => e
      m.reply "error googledefining #{what}"
      return
    end

    debug html
    results = html.scan(GOOGLE_DEF_RESULT)
    debug "results: #{results.inspect}"

    if results.length != 1
      m.reply "couldn't find a definition for #{what} on Google"
      return
    end

    head = results[0][0].ircify_html
    text = results[0][1].ircify_html
    link = results[0][2]
    m.reply "#{head} -- #{link}\n#{text}"
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

  def unpedia(m, params)
    site = "uncyclopedia.org"
    debug "Looking up things on #{site}"
    params[:site] = site
    params[:filter] = / - Uncyclopedia.*$/
    params[:hits] = @bot.config['wikipedia.hits']
    params[:firstpar] = @bot.config['wikipedia.first_par']
    return google(m, params)
  end

  def gtime(m, params)
    where = params[:words].to_s
    where.sub!(/^\s*in\s*/, '')
    searchfor = CGI.escape("time in " + where)
    url = GOOGLE_SEARCH + searchfor

    begin
      html = @bot.httputil.get(url)
    rescue => e
      m.reply "Error googletiming #{where}"
      return
    end

    debug html
    results = html.scan(GOOGLE_TIME_RESULT)
    debug "results: #{results.inspect}"

    if results.length != 1
      m.reply "Couldn't find the time for #{where} on Google"
      return
    end

    time = results[0][0].ircify_html
    m.reply "#{time}"
  end
end

plugin = SearchPlugin.new

plugin.map "search *words", :action => 'google', :threaded => true
plugin.map "google *words", :action => 'google', :threaded => true
plugin.map "lucky *words", :action => 'lucky', :threaded => true
plugin.map "gcount *words", :action => 'gcount', :threaded => true
plugin.map "gcalc *words", :action => 'gcalc', :threaded => true
plugin.map "gdef *words", :action => 'gdef', :threaded => true
plugin.map "gtime *words", :action => 'gtime', :threaded => true
plugin.map "wp :lang *words", :action => 'wikipedia', :requirements => { :lang => /^\w\w\w?$/ }, :threaded => true
plugin.map "wp *words", :action => 'wikipedia', :threaded => true
plugin.map "unpedia *words", :action => 'unpedia', :threaded => true

