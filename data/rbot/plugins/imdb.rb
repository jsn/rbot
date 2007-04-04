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
      m = /<a href="(\/(?:title|name)\/(?:tt|nm)[0-9]+\/?)[^"]*"(?:[^>]*)>(?:[^<]*)<\/a>/.match(resp.body)
      if m
        url = m[1]
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
    type = sr.match(/^\/([^\/]+)\//)[1].downcase.intern rescue nil
    case type
    when :title
      return info_title(sr)
    when :name
      return info_name(sr)
    else
      return "#{sr}"
    end
  end

  def grab_info(info, body)
    /<div class="info">\s+<h5>#{info}:<\/h5>\s+(.*?)<\/div>/mi.match(body)[1] rescue nil
  end

  def info_title(sr)
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

      plot = nil
      data = grab_info(/Plot (?:Outline|Summary)/, resp.body)
      if data
        plot = "Plot: #{data.ircify_html.gsub(/\s+more$/,'')}"
      end

      genre = Array.new
      resp.body.scan(/<a href="\/Sections\/Genres\/[^\/]+\/">([^<]+)<\/a>/) do |gnr|
        genre << gnr
      end
      info = "#{title} : http://us.imdb.com#{sr}\n"
      info << "Ratings: #{score}/10 (#{votes} voters). Genre: #{genre.join('/')}\n"
      info << plot if plot
      return info
    end
    return nil
  end

  def info_name(sr)
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
      name = CGI.unescapeHTML(m[1])

      birth = nil
      data = grab_info("Date of Birth", resp.body)
      if data
        birth = "Birth: #{data.ircify_html.gsub(/\s+more$/,'')}"
      end

      death = nil
      data = grab_info("Date of Death", resp.body)
      if data
        death = "Death: #{data.ircify_html.gsub(/\s+more$/,'')}"
      end

      awards = nil
      data = grab_info("Awards", resp.body)
      if data
        awards = "Awards: #{data.ircify_html.gsub(/\s+more$/,'')}"
      end

      info = "#{name} : http://us.imdb.com#{sr}\n"
      info << [birth, death].compact.join('. ') << "\n"
      info << awards if awards
      return info

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
    m.reply info
  end
end

plugin = ImdbPlugin.new
plugin.map "imdb *what"

