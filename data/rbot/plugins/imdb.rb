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

class Imdb
  IMDB = "http://www.imdb.com"
  TITLE_OR_NAME_MATCH = /<a\s+href="(\/(?:title|name)\/(?:tt|nm)[0-9]+\/?)[^"]*"(?:[^>]*)>([^<]*)<\/a>/
  TITLE_MATCH = /<a\s+href="(\/title\/tt[0-9]+\/?)[^"]*"(?:[^>]*)>([^<]*)<\/a>/
  NAME_MATCH = /<a\s+href="(\/name\/nm[0-9]+\/?)[^"]*"(?:[^>]*)>([^<]*)<\/a>/
  CHAR_MATCH = /<a\s+href="(\/character\/ch[0-9]+\/?)[^"]*"(?:[^>]*)>([^<]*)<\/a>/
  CREDIT_NAME_MATCH = /#{NAME_MATCH}\s*<\/td>\s*<td[^>]+>\s*\.\.\.\s*<\/td>\s*<td[^>]+>\s*(.+?)\s*<\/td>/m
  FINAL_ARTICLE_MATCH = /, ([A-Z]\S{0,2})$/
  DESC_MATCH = /<meta name="description" content="(.*?)\. (.*?)\. (.*?)\."\s*\/>/

  MATCHER = {
    :character => CHAR_MATCH,
    :title => TITLE_MATCH,
    :name => NAME_MATCH,
    :both => TITLE_OR_NAME_MATCH
  }

  def initialize(bot)
    @bot = bot
  end

  def search(rawstr, rawopts={})
    str = CGI.escape(rawstr)
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
      if opts[:all]
        return resp.body.scan(matcher).map { |m| m.first }.compact.uniq
      end
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
        results << info_title(sr, opts)
      when :name
        results << info_name(sr, opts)
      else
        results << "#{sr}"
      end
    }
    return results
  end

  def grab_info(info, body)
    /<div (?:id="\S+-info" )?class="(?:txt-block|see-more inline canwrap)">\s*<h[45](?: class="inline")?>\s*#{info}:\s*<\/h[45]>\s*(.*?)<\/div>/mi.match(body)[1] rescue nil
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

  def info_title(sr, opts={})
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
      title_date = m[1].ircify_html
      debug title_date
      # note that the date dash for series is a - (ndash), not a - (minus sign)
      # also, the second date, if missing, is an no-break space
      pre_title, extra, date, junk = title_date.scan(/^(.*)\((.+?\s+)?(\d\d\d\d(?:–(?:\d\d\d\d| )?)?(?:\/[IV]+)?)\)\s*(.+)?$/).first
      extra.strip! if extra
      pre_title.strip!
      title = fix_article(pre_title)

      dir = nil
      data = grab_info(/(?:Director|Creator)s?/, resp.body)
      if data
        dir = data.scan(NAME_MATCH).map { |url, name|
          name.ircify_html
        }.join(', ')
      end

      country = nil
      data = grab_info(/Country/, resp.body)
      if data
        country = data.ircify_html.gsub(' / ','/')
      end

      info << [title, "(#{country}, #{date})", extra, dir ? "[#{dir}]" : nil, opts[:nourl] ? nil : ": http://www.imdb.com#{sr}"].compact.join(" ")

      return info if opts[:title_only]

      if opts[:characters]
        info << resp.body.scan(CREDIT_NAME_MATCH).map { |url, name, role|
          "%s: %s" % [name, role.ircify_html]
        }.join('; ')
        return info
      end

      ratings = "no votes"
      m = resp.body.match(/Users rated this ([0-9.]+)\/10 \(([0-9,]+) votes\)/m)
      if m
        ratings = "#{m[1]}/10 (#{m[2]} voters)"
      end

      genre = Array.new
      resp.body.scan(/<a href="\/genre\/[^"]+"[^>]+>([^<]+)<\/a>/) do |gnr|
        genre << gnr
      end

      plot = resp.body.match(DESC_MATCH)[3] rescue nil
      # TODO option to extract the long storyline
      # data = resp.body.match(/<h2>Storyline<\/h2>\s+/m).post_match.match(/<\/p>/).pre_match rescue nil
      # if data
      #   data.sub!(/<em class="nobr">Written by.*$/m, '')
      #   plot = data.ircify_html.gsub(/\s+more\s*$/,'').gsub(/\s+Full summary » \| Full synopsis »\s*$/,'')
      # end
      plot = "Plot: #{plot}" if plot

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
      name = m[1].sub(/ - IMDb/, '')

      info << name
      info.last << " : http://www.imdb.com#{sr}" unless opts[:nourl]

      return info if opts[:name_only]

      if opts[:movies_by_year]
        filmoyear = @bot.httputil.get(IMDB + sr + "filmoyear")
        if filmoyear
          info << filmoyear.scan(/#{TITLE_MATCH} \((\d\d\d\d)\)[^\[\n]*((?:\s+\[[^\]]+\](?:\s+\([^\[<]+\))*)+)\s+</)
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

  def year_movies(urls, years_txt_org, role_req)
    years_txt = years_txt_org.dup
    years_txt.sub!(/^'/,'')
    years_txt = "9#{years_txt}" if years_txt.match(/^\d\ds?$/)
    years_txt = "1#{years_txt}" if years_txt.match(/^\d\d\ds?$/)

    years = []
    case years_txt
    when /^\d\d\d\d$/
      years << years_txt
    when /^(\d\d\d\d)s$/
      base = $1.to_i
      base.upto(base+9) { |year|
        years << year.to_s
      }
    end

    urls.map { |u|
      info = info_name(u, :movies_by_year => true)

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
      }.each { |url, pre_title, year, pre_roles|
        next unless years.include?(year)
        title = fix_article(pre_title.ircify_html)
        if title[0] == ?" and not @bot.config['imdb.tv_series_in_movies']
          next
        end
        title << " (#{year})" unless years.length == 1
        role_array = []
        pre_roles.strip.scan(/\[([^\]]+)\]((?:\s+\([^\[]+\))+)?/) { |txt, comm|
          role = nil
          extra = nil
          if txt.match(/^(.*)\s+\.\.\.\.\s+(.*)$/)
            role = $1
            extra = "(#{$2.ircify_html})"
          else
            role = txt
          end
          next if role_req and not role.match(/^#{role_req}/i)
          if comm
            extra ||= ""
            extra += comm.ircify_html if comm
          end
          role_array << [role, extra]
        }
        next if role_req and role_array.empty?

        roles = role_array.map { |ar|
          if role_req
            ar[1] # works for us both if it's nil and if it's something
          else
            ar.compact.join(" ")
          end
        }.compact.join(', ')
        roles = nil if roles.empty?
        movies << [roles, title].compact.join(": ")
      }

      if movies.empty?
        [name_url, nil]
      else
        [name_url, movies.join(" | ")]
      end
    }
  end

  def name_in_movie(name_urls, movie_urls)
    debug name_urls
    info = []
    movie_urls.each { |movie|
      title_info = info_title(movie, :title_only => true)
      valid = []

      data = @bot.httputil.get(IMDB + movie + "fullcredits")
      data.scan(CREDIT_NAME_MATCH).each { |url, name, role_data|
        ch_url, role = role_data.scan(CHAR_MATCH).first
        debug [ch_url, role]
        wanted = name_urls.include?(url) || name_urls.include?(ch_url)
        valid << [url, name.ircify_html, role.ircify_html] if wanted
      }
      valid.each { |url, name, role|
        info << "%s : %s was %s in %s" % [name, IMDB + url, role, title_info]
      }
    }
    return info
  end


end

class ImdbPlugin < Plugin
  Config.register Config::BooleanValue.new('imdb.aka',
    :default => true,
    :desc => "Look for IMDB matches also in translated titles and other 'also known as' information")
  Config.register Config::BooleanValue.new('imdb.popular',
    :default => true,
    :desc => "Display info on popular IMDB entries matching the request closely")
  Config.register Config::BooleanValue.new('imdb.exact',
    :default => true,
    :desc => "Display info on IMDB entries matching the request exactly")
  Config.register Config::BooleanValue.new('imdb.fix_article',
    :default => false,
    :desc => "Try to detect an article placed at the end and move it in front of the title")
  Config.register Config::BooleanValue.new('imdb.tv_series_in_movies',
    :default => false,
    :desc => "Whether searching movies by person/year should also return TV series")

  def help(plugin, topic="")
    case plugin
    when "movies"
      "movies by <who> in <years> [as <role>] => display the movies in the <years> where which <who> was <role>; <role> can be one of actor, actress, director or anything: if it's omitted, the role is defined by the prefix: \"movies by ...\" implies director, \"movies with ...\" implies actor or actress; the years can be specified as \"in the 60s\" or as \"in 1953\""
    when /characters?/
      "character played by <who> in <movie> => show the character played by <who> in movie <movie>. characters in <movie> => show the actors and characters in movie <movie>"
    else
      "imdb <string> => search http://www.imdb.org for <string>: prefix <string> with 'name' or 'title' if you only want to search for people or films respectively, e.g.: imdb name ed wood. see also movies and characters"
    end
  end

  attr_reader :i

  TITLE_URL = %r{^http://(?:[^.]+\.)?imdb.com(/title/tt\d+/)}
  NAME_URL = %r{^http://(?:[^.]+\.)?imdb.com(/name/nm\d+/)}
  def imdb_filter(s)
    loc = Utils.check_location(s, TITLE_URL)
    if loc
      sr = loc.first.match(TITLE_URL)[1]
      extra = $2 # nothign for the time being, could be fullcredits or whatever
      res = i.info_title(sr, :nourl => true, :characters => (extra == 'fullcredits'))
      debug res
      if res
        return {:title => res.first, :content => res.last}
      else
        return nil
      end
    end
    loc = Utils.check_location(s, NAME_URL)
    if loc
      sr = loc.first.match(NAME_URL)[1]
      extra = $2 # nothing for the time being, could be filmoyear or whatever
      res = i.info_name(sr, :nourl => true, :movies_by_year => (extra == 'filmoyear'))
      debug res
      if res
        name = res.shift
        return {:title => name, :content => res.join(". ")}
      else
        return nil
      end
    end
    return nil
  end

  def initialize
    super
    @i = Imdb.new(@bot)
    @bot.register_filter(:imdb, :htmlinfo) { |s| imdb_filter(s) }
  end

  # Find a person or movie on IMDB. A :type (name/title, default both) can be
  # specified to limit the search to either.
  #
  def imdb(m, params)
    if params[:movie]
      movie = params[:movie].to_s
      info = i.info(movie, :type => :title, :characters => true)
    else
      what = params[:what].to_s
      type = params[:type].intern
      info = i.info(what, :type => type)
      if !info
        m.reply "nothing found for #{what}"
        return nil
      end
    end
    if info.length == 1
      m.reply Utils.decode_html_entities(info.first.join("\n"))
    else
      m.reply info.map { |si|
        Utils.decode_html_entities si.join(" | ")
      }.join("\n")
    end
  end

  # Find the movies with a participation of :who in the year :year
  # TODO: allow year to be either a year or a decade ('[in the] 1960s')
  #
  def movies(m, params)
    who = params[:who].to_s
    years = params[:years]
    role = params[:role]
    if role and role.downcase == 'anything'
      role = nil
    elsif not role
      case params[:prefix].intern
      when :with
        role = /actor|actress/i
      when :by
        role = 'director'
      end
    end

    name_urls = i.search(who, :type => :name)
    unless name_urls
      m.reply "nothing found about #{who}, sorry"
      return
    end

    movie_urls = i.year_movies(name_urls, years, role)
    debug movie_urls.inspect
    debug movie_urls[0][1]

    if movie_urls.length == 1 and movie_urls[0][1]
      m.reply movie_urls.join("\n")
    else
      m.reply movie_urls.map { |si|
        si[1] = "no movies in #{years}" unless si[1]
        Utils.decode_html_entities si.join(" | ")
      }.join("\n")
    end
  end

  # Find the character played by :who in :movie
  #
  def character(m, params)
    movie = params[:movie].to_s
    movie_urls = i.search(movie, :type => :title)
    unless movie_urls
      m.reply "movie #{who} not found, sorry"
      return
    end

    if params[:actor]
      who = params[:actor].to_s
      type = :name
    else
      who = params[:character].to_s
      type = :character
    end

    name_urls = i.search(who, :type => type, :all => true)
    unless name_urls
      m.reply "nothing found about #{who}, sorry"
      return
    end

    info = i.name_in_movie(name_urls, movie_urls)
    if info.empty?
      m.reply "nothing found about #{who} in #{movie}, sorry"
    else
      m.reply info.join("\n")
    end
  end

  # Report the characters in movie :movie
  #
  def characters(m, params)
    movie = params[:movie].to_s

    urls = i.search(movie, :type => :title)
    unless urls
      m.reply "nothing found about #{movie}"
    end

  end

end

plugin = ImdbPlugin.new

plugin.map "imdb [:type] *what", :requirements => { :type => /name|title/ }, :defaults => { :type => 'both' }
plugin.map "movies :prefix *who in [the] :years [as :role]", :requirements => { :prefix => /with|by|from/, :years => /'?\d+s?/ }
plugin.map "character [played] by *actor in *movie"
plugin.map "character of *character in *movie"
plugin.map "characters in *movie", :action => :imdb

