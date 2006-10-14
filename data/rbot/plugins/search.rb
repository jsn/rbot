require 'uri'

Net::HTTP.version_1_2

GOOGLE_WAP_LINK = /<a accesskey="(\d)" href=".*?u=(.*?)">(.*?)<\/a>/im

class SearchPlugin < Plugin
  def help(plugin, topic="")
    case topic
    when "search"
    "search <string> => search google for <string>"
    when "google"
    "google <string> => search google for <string>"
    when "wp"
      "wp [<code>] <string> => search for <string> on Wikipedia. You can select a national <code> to only search the national Wikipedia"
    else
    "search <string> (or: google <string>) => search google for <string> | wp <string> => search for <string> on Wikipedia"
    end
  end

  def google(m, params)
    what = params[:words].to_s
    searchfor = URI.escape what
    if params[:site]
      site = "site:#{params[:site]}+"
    else
      site = ""
    end

    url = "http://www.google.com/wml/search?q=#{site}#{searchfor}"


    begin
      wml = @bot.httputil.get(url)
    rescue => e
      m.reply "error googling for #{what}"
      return
    end
    results = wml.scan(GOOGLE_WAP_LINK)
    if results.length == 0
      m.reply "no results found for #{what}"
      return
    end
    results = results[0...3].map { |res|
      "#{res[0]}. #{Bold}#{Utils.decode_html_entities res[2].strip}#{Bold}: #{URI.unescape res[1].strip}"
    }.join(" | ")

    m.reply "Results for #{what}: #{results}"
  end

  def wikipedia(m, params)
    lang = params[:lang]
    site = "#{lang.nil? ? '' : lang + '.'}wikipedia.org"
    params[:site] = site
    return google(m, params)
  end
end

plugin = SearchPlugin.new

plugin.map "search *words", :action => 'google'
plugin.map "google *words", :action => 'google'
plugin.map "wp :lang *words", :action => 'wikipedia', :requirements => { :lang => /^\w\w\w?$/ }
plugin.map "wp *words", :action => 'wikipedia'

