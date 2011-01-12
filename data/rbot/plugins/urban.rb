class UrbanPlugin < Plugin
  URBAN = 'http://www.urbandictionary.com/define.php?term='

  def help( plugin, topic="")
    "urban [word] [n]: give the [n]th definition of [word] from urbandictionary.com. urbanday: give the word-of-the-day at urban"
  end

  def format_definition(total, num, word, desc, ex)
    "#{Bold}#{word} (#{num}/#{total})#{Bold}: " +
    desc.ircify_html(:limit => 300) + " " +
    "<i>#{ex}</i>".ircify_html(:limit => 100)
  end

  def get_def(m, word, n = nil)
    n = n ? n.to_i : 1
    p = (n-1)/7 + 1
    u = URBAN + URI.escape(word)
    u += '&page=' + p.to_s if p > 1
    s = @bot.httputil.get(u)
    return m.reply("Couldn't get the urban dictionary definition for #{word}") if s.nil?

    notfound = s.match %r{<i>.*?</i> isn't defined}

    numpages = if s[%r{<div id='paginator'>.*?</div>}m]
      $&.scan(/\d+/).collect {|x| x.to_i}.max || 1
    else 1 end

    rv = Array.new
    s.scan(%r{<td class='index'[^>]*>.*?(\d+)\..*?</td>.*?<td class='word'>(?:<a.*?>)?([^>]+)(?:</a>)?</td>.*?<div class="definition">(.+?)</div>.*?<div class="example">(.+?)</div>}m) do |num, wrd, desc, ex|
      rv << [num.to_i, wrd.strip, desc.strip, ex.strip]
    end

    maxnum = rv.collect {|x| x[0]}.max || 0
    return m.reply("#{Bold}#{word}#{Bold} not found") if rv.empty?

    if notfound
      suggestions = rv.map { |str| Underline + str[1] + Underline }.uniq.join ', '
      m.reply "#{Bold}#{word}#{Bold} not found. maybe you mean #{suggestions}?"
      return
    end

    answer = rv.find { |a| a[0] == n }
    answer ||= (n > maxnum ? rv.last : rv.first)
    m.reply format_definition((p == numpages ? maxnum : "#{(numpages-1)*7 + 1}+"), *answer)
  end

  def urban(m, params)
    words = params[:words].to_s
    if words.empty?
      resp = @bot.httputil.head('http://www.urbandictionary.com/random.php',
                               :max_redir => -1,
                               :cache => false)
      return m.reply("Couldn't get a random urban dictionary word") if resp.nil?
      if resp.code == "302" && (loc = resp['location'])
        words = URI.unescape(loc.match(/define.php\?term=(.*)$/)[1]) rescue nil
      end
    end
    get_def(m, words, params[:n])
  end

  def uotd(m, params)
    home = @bot.httputil.get("http://www.urbandictionary.com/daily.php")
    if home.nil?
      m.reply "Couldn't get the urban dictionary word of the day"
      return
    end
    home.match(%r{href="/define.php\?term=.*?">(.*?)<})
    wotd = $1
    debug "Urban word of the day: #{wotd}"
    if !wotd
      m.reply "Couldn't get the urban dictionary word of the day"
      return
    end
    get_def(m, wotd, 1)
  end
end

plugin = UrbanPlugin.new
plugin.map "urban *words :n", :requirements => { :n => /^-?\d+$/ }, :action => 'urban'
plugin.map "urban [*words]", :action => 'urban'
plugin.map "urbanday", :action => 'uotd'

