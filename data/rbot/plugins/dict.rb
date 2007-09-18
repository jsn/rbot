#-- vim:sw=2:et
#++
#
# :title: Dictionary lookup plugin for rbot
#
# Author:: Giuseppe "Oblomov" Bilotta <giuseppe.bilotta@gmail.com>
# Copyright:: (C) 2006-2007 Giuseppe Bilotta
# License:: GPL v2
#
# Provides a link to the definition of a word in one of the supported
# dictionaries. Currently available are
#   * the Oxford dictionary for (British) English
#   * the De Mauro/Paravia dictionary for Italian
#   * the Chambers dictionary for English (accepts both US and UK)
#
# Other plugins can use this one to check if a given word is valid in italian
# or english by using the is_italian?/is_british?/is_english? methods
#
# TODO: cache results and reuse them if get_cached returns a cache copy

DEMAURO_LEMMA = /<anchor>(.*?)(?: - (.*?))<go href="lemma.php\?ID=(\d+)"\/><\/anchor>/
CHAMBERS_LEMMA = /<p><span class="hwd">(.*?)<\/span> <span class="psa">(.*?)<\/span>(.*?)<\/p>/

class DictPlugin < Plugin
  Config.register Config::IntegerValue.new('dict.hits',
    :default => 3,
    :desc => "Number of hits to return from a dictionary lookup")
  Config.register Config::IntegerValue.new('dict.first_par',
    :default => 0,
    :desc => "When set to n > 0, the bot will return the first paragraph from the first n dictionary hits")

  def initialize
    super
    @dmurl = "http://www.demauroparavia.it/"
    @dmwapurl = "http://wap.demauroparavia.it/index.php?lemma=%s"
    @dmwaplemma = "http://wap.demauroparavia.it/lemma.php?ID=%s"
    @oxurl = "http://www.askoxford.com/concise_oed/%s"
    @chambersurl = "http://www.chambersharrap.co.uk/chambers/features/chref/chref.py/main?query=%s&title=21st"
  end


  def help(plugin, topic="")
    case topic
    when "demauro"
      return "demauro <word> => provides a link to the definition of <word> from the De Mauro/Paravia dictionary"
    when "oxford"
      return "oxford <word> => provides a link to the definition of <word> (it can also be an expression) from the Concise Oxford dictionary"
    when "chambers"
      return "chambers <word> => provides a link to the definition of <word> (it can also be an expression) from the Chambers 21st Century Dictionary"
    end
    return "<dictionary> <word>: check for <word> on <dictionary> where <dictionary> can be one of: demauro, oxford, chambers"
  end

  def demauro(m, params)
    justcheck = params[:justcheck]

    word = params[:word].downcase
    url = @dmwapurl % CGI.escape(word)
    xml = nil
    info = @bot.httputil.get_response(url) rescue nil
    xml = info.body if info
    if xml.nil?
      info = info ? " (#{info.code} - #{info.message})" : ""
      return false if justcheck
      m.reply "An error occurred while looking for #{word}#{info}"
      return
    end
    if xml=~ /Non ho trovato occorrenze per/
      return false if justcheck
      m.reply "Nothing found for #{word}"
      return
    end
    entries = xml.scan(DEMAURO_LEMMA)
    text = word
    urls = []
    if not entries.transpose.first.grep(/\b#{word}\b/)
      return false if justcheck
      text += " not found. Similar words"
    end
    return true if justcheck
    text += ": "
    n = 0
    hits = @bot.config['dict.hits']
    text += entries[0...hits].map { |ar|
      n += 1
      urls << @dmwaplemma % ar[2]
      "#{n}. #{Bold}#{ar[0]}#{Bold} - #{ar[1].gsub(/<\/?em>/,'')}: #{@dmurl}#{ar[2]}"
    }.join(" | ")
    m.reply text

    first_pars = @bot.config['dict.first_par']

    return unless first_pars > 0

    Utils.get_first_pars urls, first_pars, :message => m,
      :strip => /^.+?\s+-\s+/

  end

  def is_italian?(word)
    return demauro(nil, :word => word, :justcheck => true)
  end


  def oxford(m, params)
    justcheck = params[:justcheck]

    word = params[:word].join
    [word, word + "_1"].each { |check|
      url = @oxurl % CGI.escape(check)
      if params[:british]
        url << "?view=uk"
      end
      h = @bot.httputil.get(url, :max_redir => 5)
      if h and h.match(%r!<h2>#{word}(?:<sup>1</sup>)?</h2>!)
        m.reply("#{word} : #{url}") unless justcheck
        defn = $'
        m.reply("#{Bold}%s#{Bold}: %s" % [word, defn.ircify_html], :overlong => :truncate)
        return true
      end
    }
    return false if justcheck
    m.reply "#{word} not found"
  end

  def is_british?(word)
    return oxford(nil, :word => word, :justcheck => true, :british => true)
  end


  def chambers(m, params)
    justcheck = params[:justcheck]

    word = params[:word].to_s.downcase
    url = @chambersurl % CGI.escape(word)
    xml = nil
    info = @bot.httputil.get_response(url) rescue nil
    xml = info.body if info
    case xml
    when nil
      info = info ? " (#{info.code} - #{info.message})" : ""
      return false if justcheck
      m.reply "An error occurred while looking for #{word}#{info}"
      return
    when /Sorry, no entries for <b>.*?<\/b> were found./
      return false if justcheck
      m.reply "Nothing found for #{word}"
      return
    when /No exact matches for <b>.*?<\/b>, but the following may be helpful./
      return false if justcheck
      m.reply "Nothing found for #{word}, but see #{url} for possible suggestions"
      return
    end
    # Else, we have a hit
    return true if justcheck
    m.reply "#{word}: #{url}"
    entries = xml.scan(CHAMBERS_LEMMA)
    hits = @bot.config['dict.hits']
    entries[0...hits].map { |ar|
      m.reply(("#{Bold}%s#{Bold} #{Underline}%s#{Underline}%s" % ar).ircify_html, :overlong => :truncate)
    }
  end

  def is_english?(word)
    return chambers(nil, :word => word, :justcheck => true)
  end

end

plugin = DictPlugin.new
plugin.map 'demauro :word', :action => 'demauro'
plugin.map 'oxford *word', :action => 'oxford'
plugin.map 'chambers *word', :action => 'chambers'

