#-- vim:sw=2:et
#++
#
# :title: IMDB plugin for rbot
#
# Author:: Arnaud Cornet <arnaud.cornet@gmail.com>
# Copyright:: (C) 2005 Arnaud Cornet
# License:: MIT license
#
# Notes by Giuseppe Bilotta:
# TODO return more than one match (configurable)
# TODO why do we use CGI.unescapeHTML? shall we rely on the rbot methods?

require 'cgi'
require 'uri/common'

class Imdb
  def initialize(bot)
    @bot = bot
  end

  def search(rawstr)
    str = URI.escape(rawstr)
    resp = nil
    begin
      resp = @bot.httputil.get_response("http://us.imdb.com/find?q=#{str}",
                                        :max_redir => -1)
    rescue Exception => e
      error e.message
      warning e.backtrace.join("\n")
      return nil
    end

    if resp.code == "200"
      m = /<a href="(\/title\/tt[0-9]+\/?)[^"]*"(?:[^>]*)>([^<]*)<\/a>/.match(resp.body)
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
    resp = nil
    begin
      resp = @bot.httputil.get_response('http://us.imdb.com' + sr,
                                        :max_redir => -1)
    rescue Exception => e
      error e.message
      warning e.backtrace.join("\n")
      return nil
    end

    if resp.code == "200"
      m = /<title>([^<]*)<\/title>/.match(resp.body)
      return nil if !m
      title = CGI.unescapeHTML(m[1])

      m = /<b>([0-9.]+)\/10<\/b>\n?\r?\s+<small>\(<a href="ratings">([0-9,]+) votes?<\/a>\)<\/small>/.match(resp.body)
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

  def imdb(m, params)
    what = params[:what].to_s
    i = Imdb.new(@bot)
    info = i.info(what)
    if !info
      m.reply "Nothing found for #{what}"
      return nil
    end
    m.reply "#{info[1]} : #{info[0]}"
    m.reply "Ratings: #{info[2]}/10 (#{info[3]} voters). Genre: #{info[4].join('/')}"
  end
end

plugin = ImdbPlugin.new
plugin.map "imdb *what"

