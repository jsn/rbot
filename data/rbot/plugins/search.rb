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
GOOGLE_WAP_SEARCH = "http://www.google.com/m/search?hl=en&q="
GOOGLE_WAP_LINK = /result">(?:<div[^>]*>)?<a href="([^"]+)"[^>]*>(.*?)<\/a>/im
GOOGLE_CALC_RESULT = %r{<img src=/images/calc_img\.gif(?: width=40 height=30 alt="")?>.*?<h[1-6] class=r[^>]*><b>(.+?)</b>}
GOOGLE_COUNT_RESULT = %r{<font size=-1>Results <b>1<\/b> - <b>10<\/b> of about <b>(.*)<\/b> for}
GOOGLE_DEF_RESULT = %r{onebox_result">\s*(.*?)\s*<br/>\s*(.*?)<table}
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
    if what.match(/^define:/)
      return google_define(m, what, params)
    end

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
    hits = 1 if params[:lucky]

    first_pars = params[:firstpar] || @bot.config['google.first_par']

    single = params[:lucky] || (hits == 1 and first_pars == 1)

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
    pretty = []

    begin
      urls = Array.new

      debug results
      results.each do |res|
        t = res[1].ircify_html(:img => "[%{src} %{alt} %{dimensions}]").strip
        u = res[0]
        if u.sub!(%r{^http://www.google.com/aclk\?},'')
          u = CGI::parse(u)['adurl'].first
          debug "skipping ad for #{u}"
          next
        elsif u.sub!(%r{^http://www.google.com/gwt/x\?},'')
          u = CGI::parse(u)['u'].first
        elsif u.sub!(%r{^/url\?},'')
          u = CGI::parse(u)['q'].first
        end
        urls.push(u)
        pretty.push("%{n}%{b}%{t}%{b}%{sep}%{u}" % {
          :n => (single ? "" : "#{urls.length}. "),
          :sep => (single ? " -- " : ": "),
          :b => Bold, :t => t, :u => u
        })
        break if urls.length == hits
      end
    rescue => e
      m.reply "failed to understand what google found for #{what}"
      error e
      debug wml
      debug results
      return
    end

    if params[:lucky]
      m.reply pretty.first
      return
    end

    result_string = pretty.join(" | ")

    # If we return a single, full result, change the output to a more compact representation
    if single
      m.reply "Result for %s: %s -- %s" % [what, result_string, Utils.get_first_pars(urls, first_pars)], :overlong => :truncate
      return
    end

    m.reply "Results for #{what}: #{result_string}", :split_at => /\s+\|\s+/

    return unless first_pars > 0

    Utils.get_first_pars urls, first_pars, :message => m

  end

  def google_define(m, what, params)
    begin
      wml = @bot.httputil.get(GOOGLE_SEARCH + CGI.escape(what))
      raise unless wml
    rescue => e
      m.reply "error googling for #{what}"
      return
    end

    begin
      related_index = wml.index(/Related phrases:/, 0)
      raise unless related_index
      defs_index = wml.index(/Definitions of <b>/, related_index)
      raise unless defs_index
      defs_end = wml.index(/<input/, defs_index)
      raise unless defs_end
    rescue => e
      m.reply "no results found for #{what}"
      return
    end

    related = wml[related_index...defs_index]
    defs = wml[defs_index...defs_end]

    m.reply defs.ircify_html(:a_href => Underline), :split_at => (Underline + ' ')

  end

  def lucky(m, params)
    params.merge!(:lucky => true)
    google(m, params)
  end

  def gcalc(m, params)
    what = params[:words].to_s
    searchfor = CGI.escape(what)

    debug "Getting gcalc thing: #{searchfor.inspect}"
    url = GOOGLE_WAP_SEARCH + searchfor

    begin
      html = @bot.httputil.get(url)
    rescue => e
      m.reply "error googlecalcing #{what}"
      return
    end

    debug "#{html.size} bytes of html recieved"
    debug html

    candidates = html.match(/font-weight:bold">(.*?)<\/(?:span|div)>/)
    debug "candidates: #{candidates.inspect}"

    if candidates.nil?
      m.reply "couldn't calculate #{what}"
      return
    end
    result = candidates[1]

    debug "replying with: #{result.inspect}"
    m.reply result.ircify_html
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
    m.reply "#{head} -- #{text}"
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

