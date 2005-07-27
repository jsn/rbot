require 'net/http'
require 'uri/common'
Net::HTTP.version_1_2

class BabelPlugin < Plugin
  def help(plugin, topic="")
    "translate to <lang> <string> => translate from english to <lang>, translate from <lang> <string> => translate to english from <lang>, translate <fromlang> <tolang> <string> => translate from <fromlang> to <tolang>. Languages: en, fr, de, it, pt, es, nl"
  end
  def translate(m, params)
    langs = ["en", "fr", "de", "it", "pt", "es", "nl"]
    trans_from = params[:fromlang] ? params[:fromlang] : 'en'
    trans_to = params[:tolang] ? params[:tolang] : 'en'
    trans_text = params[:phrase].to_s
    
    query = "/babelfish/tr"
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
    resp.body.each_line do |l|
      if(l =~ /^\s+<td bgcolor=white class=s><div style=padding:10px;>(.*)<\/div>/)
        answer = $1
        # cache the answer
        if(answer.length > 0)
          @registry["#{trans_pair}/#{data_text}"] = answer
        end
        m.reply answer
        return
      end
    end
    m.reply "couldn't parse babelfish response html :("
  else
    m.reply "couldn't talk to babelfish :("
  end
  }
  end
end
plugin = BabelPlugin.new
plugin.map 'translate to :tolang *phrase'
plugin.map 'translate from :fromlang *phrase'
plugin.map 'translate :fromlang :tolang *phrase'

