require 'uri'

DEMAURO_LEMMA = /<anchor>(.*?)(?: - (.*?))<go href="lemma.php\?ID=(\d+)"\/><\/anchor>/
class DeMauroPlugin < Plugin
  def initialize
    super
    @dmurl = "http://www.demauroparavia.it/"
    @wapurl = "http://wap.demauroparavia.it/"
  end


  def help(plugin, topic="")
    return "demauro <word> => provides a link to the definition of the word from the Italian dictionary De Mauro/Paravia"
  end

  def demauro(m, params)
    parola = params[:parola].downcase
    url = @wapurl + "index.php?lemma=#{URI.escape(parola)}"
    xml = @bot.httputil.get(url)
    if xml.nil?
      info = @bot.httputil.last_response
      info = info ? "(#{info.code} - #{info.message})" : ""
      m.reply "An error occurred while looking for #{parola}#{info}"
      return
    end
    if xml=~ /Non ho trovato occorrenze per/
      m.reply "Nothing found for #{parola}"
      return
    end
    entries = xml.scan(DEMAURO_LEMMA)
    text = parola
    if !entries.assoc(parola) and !entries.assoc(parola.upcase)
      text += " not found. Similar words"
    end
    text += ": "
    text += entries[0...5].map { |ar|
      "#{ar[0]} - #{ar[1].gsub(/<\/?em>/,'')}: #{@dmurl}#{ar[2]}"
    }.join(" | ")
    m.reply text
  end
end

plugin = DeMauroPlugin.new
plugin.map 'demauro :parola', :action => 'demauro'

