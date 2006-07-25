require 'erb'

class DeMauroPlugin < Plugin
  include ERB::Util

  def initialize
    super
    @dmurl = "http://www.demauroparavia.it/"
  end


  def help(plugin, topic="")
    return "demauro <parola> => fornisce il link della definizione della parola dal dizionario De Mauro/Paravia"
  end

  def demauro(m, params)
    parola = params[:parola]
    url = @dmurl + "cerca?stringa=#{url_encode(parola)}"
    uri = URI.parse(url)
    http = @bot.httputil.get_proxy(uri)
    xml = nil
    defurls = Array.new
    begin
      http.start() { |http|
	resp = http.get(uri.request_uri())
	case resp.code
	when "200"
	  xml = resp.body
	when "302"
	  loc = resp['location']
	  if loc =~ /#{@dmurl}\d+/
	    defurls << loc
	  end
	else
	  debug resp.to_a
	end
      }
    rescue => e
      debug "HttpUtil.get exception: #{e.inspect}, while trying to get #{uri}"
      debug e.backtrace.join("\n")
      m.reply "C'è stato un errore nella ricerca"
      return
    end
    if xml
      if xml=~ /Non ho trovato occorrenze per/
	m.reply "Parola non trovata"
	return
      else
	xml.gsub(/href="(\d+)"/) { |match|
	  debug match.to_a.join(" || ")
	  defurls << "#{@dmurl}#{$1}"
	}
      end
    end
    lemmas = Array.new
    defurls.each { |url|
      uri = URI.parse(url)
      http = @bot.httputil.get_proxy(uri)
      begin
	debug "Scanning #{url}"
	http.start() { |http|
	  resp = http.get(uri.request_uri())
	  case resp.code
	  when "200"
	    debug "Got data"
	    matched = /<span class="lemma">(.*)<\/span><br\/><span class="qualifica".*?>(.*?)<\/span><br\/>/.match(resp.body)
	    dirtylemma = matched[1]
	    qual = matched[2]
	    lemma = dirtylemma.gsub(/<\/?span(?: class="pipelemma")?>/,"")
	    debug lemma
	    lemma = lemma.gsub(/<sup>1<\/sup>/,'¹').gsub(/<sup>2<\/sup>/,'²').gsub(/<sup>3<\/sup>/,'³')
	    lemma = lemma.gsub(/<sup>4<\/sup>/,'⁴').gsub(/<sup>5<\/sup>/,'⁵').gsub(/<sup>6<\/sup>/,'⁶')
	    lemma = lemma.gsub(/<sup>7<\/sup>/,'⁷').gsub(/<sup>8<\/sup>/,'⁸').gsub(/<sup>9<\/sup>/,'⁹')
	    debug lemma
	    lemma += " #{qual} (#{uri})"
	    lemmas << lemma
	  else
	    debug resp.to_a.join("\r")
	  end
	}
      rescue => e
	debug "Exception '#{e.inspect}' while trying to get and parse #{uri}"
	debug e.backtrace.join("\n")
	m.reply "C'è stato un errore nell'elaborazione del risultato"
	return
      end
    }
    pre = lemmas.length > 1 ? "Lemmi trovati" : "Lemma trovato"
    m.reply "#{pre}: #{lemmas.join(' ; ')}"
  end
end

plugin = DeMauroPlugin.new
plugin.map 'demauro :parola', :action => 'demauro'

