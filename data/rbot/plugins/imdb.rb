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
  FINAL_ARTICLE_MATCH = /, ([A-Z]\S{0,2})$/

  MATCHER = {
    :title => TITLE_MATCH,
    :name => NAME_MATCH,
    :both => TITLE_OR_NAME_MATCH
  }

  def initialize(bot)
    @bot = bot
  end

  def search(rawstr, rawopts={})
    str = URI.escape(rawstr)
    str << ";site=aka" if @bot.config['imdb.aka']
    opts = rawopts.dup
    opts[:type] = :both unless opts[:type]
    return do_search(str, opts)
  end

  def do_search(str, opts={})
    resp = nil
    begin
      resp = @bot.httputil.get_response(IMDB + "/find?q=#{str}",
                                        :max_redir => -1)
    rescue Exception => e
      error e.message
      warning e.backtrace.join("\n")
      return nil
    end


    matcher = MATCHER[opts[:type]]

    if resp.code == "200"
      m = []
      m << matcher.match(resp.body) if @bot.config['imdb.popular']
      if resp.body.match(/\(Exact Matches\)<\/b>/) and @bot.config['imdb.exact']
        m << matcher.match($')
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
        return do_search($1, opts)
      else
        return [new_loc.gsub(/\?.*/, "")]
      end
    end
    return nil
  end

  def info(rawstr, opts={})
    debug opts.inspect
    urls = search(rawstr, opts)
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

  def fix_article(org_tit)
    title = org_tit.dup
    debug title.inspect
    if title.match(/^"(.*)"$/)
      return "\"#{fix_article($1)}\""
    end
    if @bot.config['imdb.fix_article'] and title.gsub!(FINAL_ARTICLE_MATCH, '')
      art = $1.dup
      debug art.inspect
      if art[-1,1].match(/[A-Za-z]/)
        art << " "
      end
      return art + title
    end
    return title
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
      pre_title, date, extra = title_date.scan(/^(.*)\((\d\d\d\d(?:\/[IV]+)?)\)\s*(.+)?$/).first
      pre_title.strip!
      title = fix_article(pre_title.ircify_html)

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
        country = data.ircify_html.gsub(' / ','/')
      end

      info << [title, "(#{country}, #{date})", extra, dir ? "[#{dir}]" : nil, ": http://us.imdb.com#{sr}"].compact.join(" ")

      ratings = "no votes"
      m = /<b>([0-9.]+)\/10<\/b>\n?\r?\s+<small>\(<a href="ratings">([0-9,]+) votes?<\/a>\)<\/small>/.match(resp.body)
      if m
        ratings = "#{m[1]}/10 (#{m[2]} voters)"
      end

      genre = Array.new
      resp.body.scan(/<a href="\/Sections\/Genres\/[^\/]+\/">([^<]+)<\/a>/) do |gnr|
        genre << gnr
      end

      plot = nil
      data = grab_info(/Plot (?:Outline|Summary)/, resp.body)
      if data
        plot = "Plot: " + data.ircify_html.gsub(/\s+more$/,'')
      end

      info << ["Ratings: " << ratings, "Genre: " << genre.join('/') , plot].compact.join(". ")

      return info
    end
    return nil
  end

  def info_name(sr, opts={})
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

      if year = opts[:movies_in_year]
        filmoyear = @bot.httputil.get(IMDB + sr + "filmoyear")
        if filmoyear
          info << filmoyear.scan(/#{TITLE_MATCH} \(#{year}\)[^\[\n]*((?:\s+\[[^\]]+\](?:\s+\([^\[<]+\))*)+)\s+</)
        end
        return info
      end

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

      info << [birth, death].compact.join('. ') if birth or death

      movies = {}

      filmorate = nil
      begin
        filmorate = @bot.httputil.get(IMDB + sr + "filmorate")
      rescue Exception
      end

      if filmorate
        filmorate.scan(/<div class="filmo">.*?<a href="\/title.*?<\/div>/m) { |str|
          what = str.match(/<a name="[^"]+">([^<]+)<\/a>/)[1] rescue nil
          next unless what
          movies[what] = str.scan(TITLE_MATCH)[0..2].map { |url, tit|
            fix_article(tit.ircify_html)
          }
        }
      end

      preferred = ['Actor', 'Director']
      if resp.body.match(/Jump to filmography as:&nbsp;(.*?)<\/div>/)
        txt = $1
        preferred = txt.scan(/<a[^>]+>([^<]+)<\/a>/)[0..2].map { |pref|
          pref.first
        }
      end

      unless movies.empty?
        all_keys = movies.keys.sort
        debug all_keys.inspect
        keys = []
        preferred.each { |key|
          keys << key if all_keys.include? key
        }
        keys = all_keys if keys.empty?
        ar = []
        keys.each { |key|
          ar << key.dup
          ar.last << ": " + movies[key].join('; ')
        }
        info << ar.join('. ')
      end
      return info

    end
    return nil
  end

  def year_movies(urls, year)
    urls.map { |url|
      info = info_name(url, :movies_in_year => year)

      debug info.inspect

      name_url = info.first
      data = info[1]

      movies = []
      # Sort by pre-title putting movies before TV series
      data.sort { |a, b|
        aclip = a[1][0,5]
        bclip = b[1][0,5]
        quot = '&#34;'
        (aclip == quot ? 1 : -1) <=> (bclip == quot ? 1 : -1)
      }.each { |url, pre_title, pre_roles|
        title = fix_article(pre_title.ircify_html)
        role_array = []
        pre_roles.strip.scan(/\[([^\]]+)\]((?:\s+\([^\[]+\))+)?/) { |txt, comm|
          if txt.match(/^(.*)\s+\.\.\.\.\s+(.*)$/)
            role_array << "#{$1} (#{$2})"
          else
            role_array << txt
          end
          role_array.last << " " + comm.ircify_html if comm
        }

        roles = role_array.join(', ')
        movies << [roles, title].join(": ")
      }

      if movies.empty?
        [name_url, nil]
      else
        [name_url, movies.join(" | ")]
      end
    }
  end

end

class ImdbPlugin < Plugin
  BotConfig.register BotConfigBooleanValue.new('imdb.aka',
    :default => true,
    :desc => "Look for IMDB matches also in translated titles and other 'also known as' information")
  BotConfig.register BotConfigBooleanValue.new('imdb.popular',
    :default => true,
    :desc => "Display info on popular IMDB entries matching the request closely")
  BotConfig.register BotConfigBooleanValue.new('imdb.exact',
    :default => true,
    :desc => "Display info on IMDB entries matching the request exactly")
  BotConfig.register BotConfigBooleanValue.new('imdb.fix_article',
    :default => false,
    :desc => "Try to detect an article placed at the end and move it in front of the title")

  def help(plugin, topic="")
    "imdb <string> => search http://www.imdb.org for <string>: prefix <string> with 'name' or 'title' if you only want to search for people or films respectively, e.g.: imdb name ed wood"
  end

  attr_reader :i

  def initialize
    super
    @i = Imdb.new(@bot)
  end

  def imdb(m, params)
    what = params[:what].to_s
    type = params[:type].intern
    info = i.info(what, :type => type)
    if !info
      m.reply "Nothing found for #{what}"
      return nil
    end
    if info.length == 1
      m.reply Utils.decode_html_entities info.first.join("\n")
    else
      m.reply info.map { |si|
        Utils.decode_html_entities si.join(" | ")
      }.join("\n")
    end
  end

  def movies(m, params)
    who = params[:who].to_s
    year = params[:year]

    name_urls = i.search(who, :type => :name)
    unless name_urls
      m.reply "nothing found about #{who}, sorry"
      return
    end

    movie_urls = i.year_movies(name_urls, year)
    debug movie_urls.inspect
    debug movie_urls[0][1]

    if movie_urls.length == 1 and movie_urls[0][1]
      m.reply movie_urls.join("\n")
    else
      m.reply movie_urls.map { |si|
        si[1] = "no movies in #{year}" unless si[1]
        Utils.decode_html_entities si.join(" | ")
      }.join("\n")
    end
  end

end

plugin = ImdbPlugin.new
plugin.map "movies :prefix *who in :year", :requirements => { :prefix => /with|by|from/, :year => /\d+/ }
plugin.map "imdb [:type] *what", :requirements => { :type => /name|title/ }, :defaults => { :type => 'both' }

