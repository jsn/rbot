require 'uri'

Net::HTTP.version_1_2

GOOGLE_WAP_LINK = /<a accesskey="(\d)" href=".*?u=(.*?)">(.*?)<\/a>/im

class SearchPlugin < Plugin
  def help(plugin, topic="")
    "google <string> => search google for <string>"
  end

  def google(m, params)
    what = params[:words].to_s
    searchfor = URI.escape what

    url = "http://www.google.com/wml/search?q=#{searchfor}"


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
end

plugin = SearchPlugin.new

plugin.map "search *words", :action => 'google'
plugin.map "google *words", :action => 'google'

