# vim: set sw=2 et:
#
# dict plugin: provides a link to the definition of a word in one of the supported
# dictionaries. Currently available are
#   * the Oxford dictionary for (British) English
#   * the De Mauro/Paravia dictionary for Italian
#   * the Chambers dictionary for English (accepts both US and UK)
#
# other plugins can use this one to check if a given word is valid in italian
# or english by using the is_italian?/is_british?/is_english? methods
#
# Author: Giuseppe "Oblomov" Bilotta <giuseppe.bilotta@gmail.com>
#
# TODO: cache results and reuse them if get_cached returns a cache copy

require 'uri'

DEMAURO_LEMMA = /<anchor>(.*?)(?: - (.*?))<go href="lemma.php\?ID=(\d+)"\/><\/anchor>/

class DictPlugin < Plugin
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
    url = @dmwapurl % URI.escape(word)
    xml = @bot.httputil.get_cached(url)
    if xml.nil?
      info = @bot.httputil.last_response
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
    if !entries.assoc(word) and !entries.assoc(word.upcase)
      return false if justcheck
      text += " not found. Similar words"
    end
    return true if justcheck
    text += ": "
    n = 0
    text += entries[0...5].map { |ar|
      n += 1
      urls << @dmwaplemma % ar[2]
      "#{n}. #{Bold}#{ar[0]}#{Bold} - #{ar[1].gsub(/<\/?em>/,'')}: #{@dmurl}#{ar[2]}"
    }.join(" | ")
    m.reply text

    Utils.get_first_pars urls, 5, :http_util => @bot.httputil, :message => m

  end

  def is_italian?(word)
    return demauro(nil, :word => word, :justcheck => true)
  end


  def oxford(m, params)
    justcheck = params[:justcheck]

    word = params[:word].join
    [word, word + "_1"].each { |check|
      url = @oxurl % URI.escape(check)
      h = @bot.httputil.head(url)
      if h
        m.reply("#{word} found: #{url}") unless justcheck
        return true
      end
    }
    return false if justcheck
    m.reply "#{word} not found"
  end

  def is_british?(word)
    return oxford(nil, :word => word, :justcheck => true)
  end


  def chambers(m, params)
    justcheck = params[:justcheck]

    word = params[:word].to_s.downcase
    url = @chambersurl % URI.escape(word)
    xml = @bot.httputil.get_cached(url)
    case xml
    when nil
      info = @bot.httputil.last_response
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
    else
      return false if justcheck
      m.reply "#{word}: #{url}"
    end
  end

  def is_english?(word)
    return chambers(nil, :word => word, :justcheck => true)
  end

end

plugin = DictPlugin.new
plugin.map 'demauro :word', :action => 'demauro'
plugin.map 'oxford *word', :action => 'oxford'
plugin.map 'chambers *word', :action => 'chambers'

