# vim: set sw=2 et:
#
# dict plugin: provides a link to the definition of a word in one of the supported
# dictionaries. Currently available are
#   * the Oxford dictionary for (British) English
#   * the De Mauro/Paravia dictionary for Italian
#
# other plugins can use this one to check if a given word is valid in italian
# or british english by using the is_italian?/is_british? methods
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
    @dmwapurl = "http://wap.demauroparavia.it/"
    @oxurl = "http://www.askoxford.com/concise_oed/"
  end


  def help(plugin, topic="")
    return "demauro <word> => provides a link to the definition of the word from the Italian dictionary De Mauro/Paravia"
  end

  def demauro(m, params)
    justcheck = params[:justcheck]

    word = params[:word].downcase
    url = @dmwapurl + "index.php?lemma=#{URI.escape(word)}"
    xml = @bot.httputil.get_cached(url)
    if xml.nil?
      info = @bot.httputil.last_response
      info = info ? "(#{info.code} - #{info.message})" : ""
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
    if !entries.assoc(word) and !entries.assoc(word.upcase)
      return false if justcheck
      text += " not found. Similar words"
    end
    return true if justcheck
    text += ": "
    text += entries[0...5].map { |ar|
      "#{ar[0]} - #{ar[1].gsub(/<\/?em>/,'')}: #{@dmurl}#{ar[2]}"
    }.join(" | ")
    m.reply text
  end

  def is_italian?(word)
    return demauro(nil, :word => word, :justcheck => true)
  end


  def oxford(m, params)
    justcheck = params[:justcheck]

    word = params[:word].downcase.gsub(/\s+/,'')
    [word, word + "_1"].each { |check|
      url = @oxurl + "#{URI.escape(check)}"
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

end

plugin = DictPlugin.new
plugin.map 'demauro :word', :action => 'demauro'
plugin.map 'oxford :word', :action => 'oxford'

