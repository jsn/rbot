require 'net/http'
require 'uri/common'
Net::HTTP.version_1_2

class BabelPlugin < Plugin
  LANGS = %w{en fr de it pt es nl ru zh zt el ja ko}

  BotConfig.register BotConfigEnumValue.new('translate.default_from',
    :values => LANGS, :default => 'en',
    :desc => "Default language to translate from")
  BotConfig.register BotConfigEnumValue.new('translate.default_to',
    :values => LANGS, :default => 'en',
    :desc => "Default language to translate to")

  def help(plugin, topic="")
    from = @bot.config['translate.default_from']
    to = @bot.config['translate.default_to']
    "translate to <lang> <string> => translate from #{from} to <lang>, translate from <lang> <string> => translate to #{to} from <lang>, translate <fromlang> <tolang> <string> => translate from <fromlang> to <tolang>. If <string> is an http url, translates the referenced webpage and returns the 1st content paragraph. Languages: #{LANGS.join(', ')}"
  end

  def translate(m, params)
    langs = LANGS
    trans_from = params[:fromlang] ? params[:fromlang] : @bot.config['translate.default_from']
    trans_to = params[:tolang] ? params[:tolang] : @bot.config['translate.default_to']
    trans_text = params[:phrase].to_s
    
    lang_match = langs.join("|")
    unless(trans_from =~ /^(#{lang_match})$/ && trans_to =~ /^(#{lang_match})$/)
      m.reply "invalid language: valid languagess are: #{langs.join(' ')}"
      return
    end

    data_text = URI.escape trans_text
    trans_pair = "#{trans_from}_#{trans_to}"

    if (trans_text =~ /^http:\/\//) && (URI.parse(trans_text) rescue nil)
      url = 'http://babelfish.altavista.com/babelfish/trurl_pagecontent' +
        "?lp=#{trans_pair}&url=#{data_text}"

      return Utils.get_first_pars([url], 1, :message => m)
    end

    data = "lp=#{trans_pair}&doit=done&intl=1&tt=urltext&urltext=#{data_text}"

    # check cache for previous lookups
    if @registry.has_key?("#{trans_pair}/#{data_text}")
      m.reply @registry["#{trans_pair}/#{data_text}"]
      return
    end

    headers = {
      "content-type" => "application/x-www-form-urlencoded; charset=utf-8"
    }

    query = "/babelfish/tr"

    begin
      resp = @bot.httputil.get_response('http://babelfish.altavista.com'+query,
                                        :method => :post,
                                        :body => data,
                                        :headers => headers)
    rescue Exception => e
      m.reply "http error: #{e.message}"
      return
    end

    if (resp.code == "200")
      lines = Array.new
      resp.body.each_line { |l| lines.push l }

      l = lines.join(" ")
      debug "babelfish response: #{l}"

      case l
      when /^\s+<td bgcolor=white class=s><div style=padding:10px;>(.*)<\/div><\/td>\s*<\/tr>/m
        answer = $1.gsub(/\s*[\r\n]+\s*/,' ')
        # cache the answer
        if(answer.length > 0)
          @registry["#{trans_pair}/#{data_text}"] = answer
        end
        m.reply answer
        return
      when /^\s+<option value="#{trans_pair}"\s+SELECTED>/
        m.reply "couldn't parse babelfish response html :("
      else
        m.reply "babelfish doesn't support translation from #{trans_from} to #{trans_to}"
      end
    else
      m.reply "couldn't talk to babelfish :("
    end
  end
end
plugin = BabelPlugin.new
plugin.map 'translate to :tolang *phrase'
plugin.map 'translate from :fromlang *phrase'
plugin.map 'translate :fromlang :tolang *phrase'

