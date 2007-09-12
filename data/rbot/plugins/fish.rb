class BabelPlugin < Plugin
  LANGS = %w{en fr de it pt es nl ru zh zt el ja ko}

  Config.register Config::EnumValue.new('translate.default_from',
    :values => LANGS, :default => 'en',
    :desc => "Default language to translate from")
  Config.register Config::EnumValue.new('translate.default_to',
    :values => LANGS, :default => 'en',
    :desc => "Default language to translate to")

  def help(plugin, topic="")
    case topic
    when 'cache'
      "translate cache [view|clear] => view or clear the translate cache contents"
    else
      from = @bot.config['translate.default_from']
      to = @bot.config['translate.default_to']
      "translate to <lang> <string> => translate from #{from} to <lang>, translate from <lang> <string> => translate to #{to} from <lang>, translate <fromlang> <tolang> <string> => translate from <fromlang> to <tolang>. If <string> is an http url, translates the referenced webpage and returns the 1st content paragraph. Languages: #{LANGS.join(', ')}. Other topics: cache"
    end
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

    data_text = CGI.escape trans_text
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
      body = @bot.httputil.get('http://babelfish.altavista.com'+query,
                               :method => :post,
                               :body => data,
                               :headers => headers)
    rescue Exception => e
      m.reply "http error: #{e.message}"
      return
    end

    case body
    when nil
      m.reply "couldn't talk to babelfish :("
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
  end

  def cache_mgmt(m, params)
    cmd = params[:cmd].intern
    case cmd
    when :view
      cache = []
      @registry.each { |key, val|
        cache << "%s => %s" % [key, val]
      }
      m.reply "translate cache: #{cache.inspect}"
    when :clear
      keys = []
      @registry.each { |key, val|
        keys << key
      }
      keys.each { |key|
        @registry.delete(key)
      }
      cache_mgmt(m, :cmd => 'view')
    end
  end

end

plugin = BabelPlugin.new

plugin.default_auth('cache', false)

plugin.map 'translate to :tolang *phrase', :thread => true
plugin.map 'translate from :fromlang *phrase', :thread => true
plugin.map 'translate cache :cmd', :action => :cache_mgmt, :auth_path => 'cache!', :requirements => { :cmd => /view|clear/ }
plugin.map 'translate :fromlang :tolang *phrase', :thread => true

