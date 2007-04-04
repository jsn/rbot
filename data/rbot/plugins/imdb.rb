#-- vim:sw=2:et
#++
#
# :title: IMDB plugin for rbot
#
# Author:: Arnaud Cornet <arnaud.cornet@gmail.com>
# Author:: Giuseppe "Oblomov" Bilotta <giuseppe.bilotta@gmail.com>
#
# Copyright:: (C) 2005 Arnaud Cornet
# Copyright:: (C) 2007 Giuseppe Bilotta
#
# License:: MIT license

require 'uri/common'

class Imdb
  IMDB = "http://us.imdb.com"
  TITLE_OR_NAME_MATCH = /<a href="(\/(?:title|name)\/(?:tt|nm)[0-9]+\/?)[^"]*"(?:[^>]*)>([^<]*)<\/a>/
  TITLE_MATCH = /<a href="(\/title\/tt[0-9]+\/?)[^"]*"(?:[^>]*)>([^<]*)<\/a>/
  NAME_MATCH = /<a href="(\/name\/nm[0-9]+\/?)[^"]*"(?:[^>]*)>([^<]*)<\/a>/

  def initialize(bot)
    @bot = bot
  end

  def search(rawstr)
    str = URI.escape(rawstr) << ";site=aka"
    return do_search(str)
  end

  def do_search(str)
    resp = nil
    begin
      resp = @bot.httputil.get_response(IMDB + "/find?q=#{str}",
                                        :max_redir => -1)
    rescue Exception => e
      error e.message
      warning e.backtrace.join("\n")
      return nil
    end

    if resp.code == "200"
      m = []
      m << TITLE_OR_NAME_MATCH.match(resp.body)
      if resp.body.match(/\(Exact Matches\)<\/b>/)
        m << TITLE_OR_NAME_MATCH.match($')
      end
      m.compact!
      unless m.empty?
        return m.map { |mm|
          mm[1]
        }.uniq
      end
    elsif resp.code == "302"
      debug "automatic redirection"
      new_loc = resp['location'].gsub(IMDB, "")
      if new_loc.match(/\/find\?q=(.*)/)
        return do_search($1)
      else
        return [new_loc.gsub(/\?.*/, "")]
      end
    end
    return nil
  end

  def info(rawstr)
    urls = search(rawstr)
    debug urls
    if urls.nil_or_empty?
      debug "IMDB: search returned NIL"
      return nil
    end
    results = []
    urls.each { |sr|
      type = sr.match(/^\/([^\/]+)\//)[1].downcase.intern rescue nil
      case type
      when :title
        results << info_title(sr)
      when :name
        results << info_name(sr)
      else
        results << "#{sr}"
      end
    }
    return results
  end

  def grab_info(info, body)
    /<div class="info">\s+<h5>#{info}:<\/h5>\s+(.*?)<\/div>/mi.match(body)[1] rescue nil
  end

  def info_title(sr)
    resp = nil
    begin
      resp = @bot.httputil.get_response(IMDB + sr, :max_redir => -1)
    rescue Exception => e
      error e.message
      warning e.backtrace.join("\n")
      return nil
    end

    info = []

    if resp.code == "200"
      m = /<title>([^<]*)<\/title>/.match(resp.body)
      return nil if !m
      title_date = m[1]
      title, date = title_date.scan(/^(.*)\((\d\d\d\d(?:[IV]+)?)\)$/).first
      title.strip!

      dir = nil
      data = grab_info(/Directors?/, resp.body)
      if data
        dir = data.scan(NAME_MATCH).map { |url, name|
          name
        }.join(', ')
      end

      country = nil
      data = grab_info(/Country/, resp.body)
      if data
        country = data.ircify_html
      end

      info << [title, "(#{country}, #{date})", dir ? "[#{dir}]" : nil, ": http://us.imdb.com#{sr}"].compact.join(" ")

      m = /<b>([0-9.]+)\/10<\/b>\n?\r?\s+<small>\(<a href="ratings">([0-9,]+) votes?<\/a>\)<\/small>/.match(resp.body)
      return nil if !m
      score = m[1]
      votes = m[2]

      genre = Array.new
      resp.body.scan(/<a href="\/Sections\/Genres\/[^\/]+\/">([^<]+)<\/a>/) do |gnr|
        genre << gnr
      end

      info << "Ratings: #{score}/10 (#{votes} voters). Genre: #{genre.join('/')}"

      plot = nil
      data = grab_info(/Plot (?:Outline|Summary)/, resp.body)
      if data
        plot = "Plot: #{data.ircify_html.gsub(/\s+more$/,'')}"
        info << plot
      end

      return info
    end
    return nil
  end

  def info_name(sr)
    resp = nil
    begin
      resp = @bot.httputil.get_response(IMDB + sr, :max_redir => -1)
    rescue Exception => e
      error e.message
      warning e.backtrace.join("\n")
      return nil
    end

    info = []

    if resp.code == "200"
      m = /<title>([^<]*)<\/title>/.match(resp.body)
      return nil if !m
      name = m[1]

      info << "#{name} : http://us.imdb.com#{sr}"

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

      info << [birth, death].compact.join('. ')

      movies = {}

      filmorate = nil
      begin
        filmorate = @bot.httputil.get(IMDB + sr + "filmorate")
      rescue Exception
      end

      if filmorate
        filmorate.scan(/<div class="filmo">.*?<a href="\/title.*?<\/div>/m) { |str|
          what = str.match(/<a name="[^"]+">([^<]+)<\/a>/)[1] rescue nil
          # next unless what
          next unless ['Actor', 'Director'].include?(what)
          movies[what] = str.scan(TITLE_MATCH)[0..2].map { |url, tit|
            tit
          }
        }
      end

      unless movies.empty?
        ar = []
        movies.keys.sort.each { |key|
          ar << key.dup
          ar.last << ": " + movies[key].join(', ')
        }
        info << "Top Movies:: " + ar.join('. ')
      end
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
    if info.length == 1
      m.reply Utils.decode_html_entities info.first.join("\n")
    else
      m.reply info.map { |i|
        Utils.decode_html_entities i.join(" | ")
      }.join("\n")
    end
  end
end

plugin = ImdbPlugin.new
plugin.map "imdb *what"

