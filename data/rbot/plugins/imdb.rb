# IMDB plugin for RubyBot
# (c) 2005 Arnaud Cornet <arnaud.cornet@gmail.com>
# Licensed under MIT License.

require 'net/http'
require 'cgi'
require 'uri/common'

class Imdb
  def initialize(bot)
    @bot = bot
  end

  def search(rawstr)
    str = URI.escape(rawstr)
    @http = @bot.httputil.get_proxy(URI.parse("http://us.imdb.com/find?q=#{str}"))
    @http.start
    begin
    resp, data = @http.get("/find?q=#{str}", "User-Agent" => "Mozilla/5.0")
    rescue Net::ProtoRetriableError => detail
      head = detail.data
      if head.code == "301" or head.code == "302"
            return head['location'].gsub(/http:\/\/us.imdb.com/, "").gsub(/\?.*/, "")
        end
    end
    if resp.code == "200"
      m = /<a href="(\/title\/tt[0-9]+\/?)[^"]*"(:?[^>]*)>([^<]*)<\/a>/.match(resp.body)
      if m
        url = m[1]
        title = m[2]
        return url
      end
    elsif resp.code == "302"
      return resp['location'].gsub(/http:\/\/us.imdb.com/, "").gsub(/\?.*/, "")
    end
    return nil
  end

  def info(rawstr)
    sr = search(rawstr)
    if !sr
      debug "IMDB: search returned NIL"
      return nil
    end
    resp, data = @http.get(sr, "User-Agent" =>
      "Mozilla/5.0 (compatible; Konqueror/3.1; Linux)")
    if resp.code == "200"
      m = /<title>([^<]*)<\/title>/.match(resp.body)
      return nil if !m
      title = CGI.unescapeHTML(m[1])

      m = /<b>([0-9.]+)\/10<\/b> \(([0-9,]+) votes?\)/.match(resp.body)
      return nil if !m
      score = m[1]
      votes = m[2]

      genre = Array.new
      resp.body.scan(/<a href="\/Sections\/Genres\/[^\/]+\/">([^<]+)<\/a>/) do |gnr|
        genre << gnr
      end
      return ["http://us.imdb.com" + sr, title, score, votes,
        genre]
    end
    return nil
  end
end

class ImdbPlugin < Plugin
  def help(plugin, topic="")
    "imdb <string> => search http://www.imdb.org for <string>"
  end

  def privmsg(m)
    unless(m.params && m.params.length > 0)
      m.reply "incorrect usage: " + help(m.plugin)
      return
    end

    i = Imdb.new(@bot)
    info = i.info(m.params)
    if !info
      m.reply "Nothing found for #{m.params}"
      return nil
    end
    m.reply "#{info[1]} : #{info[0]}"
    m.reply "Ratings: #{info[2]}/10 (#{info[3]} voters). Genre: #{info[4].join('/')}"
  end
end

plugin = ImdbPlugin.new
plugin.register("imdb")

