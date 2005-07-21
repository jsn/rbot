require 'net/http'
require 'uri/common'
Net::HTTP.version_1_2

class BabelPlugin < Plugin
  def help(plugin, topic="")
    "translate to <lang> <string> => translate from english to <lang>, translate from <lang> <string> => translate to english from <lang>, translate <fromlang> <tolang> <string> => translate from <fromlang> to <tolang>. Languages: en, fr, de, it, pt, es, nl"
  end
  def privmsg(m)

    langs = ["en", "fr", "de", "it", "pt", "es", "nl"]

    query = "/babelfish/tr"
    if(m.params =~ /^to\s+(\S+)\s+(.*)/)
      trans_from = "en"
      trans_to = $1
      trans_text = $2
    elsif(m.params =~ /^from\s+(\S+)\s+(.*)/)
      trans_from = $1
      trans_to = "en"
      trans_text = $2
    elsif(m.params =~ /^(\S+)\s+(\S+)\s+(.*)/)
      trans_from = $1
      trans_to = $2
      trans_text = $3
    else
      m.reply "incorrect usage: " + help(m.plugin)
      return
    end
    lang_match = langs.join("|")
    unless(trans_from =~ /^(#{lang_match})$/ && trans_to =~ /^(#{lang_match})$/)
      m.reply "invalid language: valid languagess are: #{langs.join(' ')}"
      return
    end

    data_text = URI.escape trans_text
    trans_pair = "#{trans_from}_#{trans_to}"
    data = "lp=#{trans_pair}&doit=done&intl=1&tt=urltext&urltext=#{data_text}"

    # check cache for previous lookups
    if @registry.has_key?("#{trans_pair}/#{data_text}")
      m.reply @registry["#{trans_pair}/#{data_text}"]
      return
    end

    http = @bot.httputil.get_proxy(URI.parse("http://babelfish.altavista.com"))

    http.start {|http|
      resp = http.post(query, data, {"content-type",
      "application/x-www-form-urlencoded"})
	
	if (resp.code == "200")
    #puts resp.body
	resp.body.each_line {|l|
		if(l =~ /^\s+<td bgcolor=white class=s><div style=padding:10px;>(.*)<\/div>/)
	  		answer = $1
	  		# cache the answer
	     		if(answer.length > 0)
	     			@registry["#{trans_pair}/#{data_text}"] = answer
	    		end
	    		m.reply answer
			return
	     	end
	}
		m.reply "couldn't parse babelfish response html :("
	else
		m.reply "couldn't talk to babelfish :("
	end
	}
  end
end
plugin = BabelPlugin.new
plugin.register("translate")

