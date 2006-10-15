require 'uri'

class UrbanPlugin < Plugin

  def help( plugin, topic="")
    "urban [word] [n]: give the [n]th definition of [word] from urbandictionary.com. urbanday: give the word-of-the-day at urban"
  end

  def urban(m, params)
    words = params[:words].to_s
    n = params[:n].nil? ? 1 : params[:n].to_i rescue 1

    if words.empty?
      uri = URI.parse( "http://www.urbandictionary.com/random.php" )
      @bot.httputil.head(uri) { |redir|
        words = URI.unescape(redir.match(/define.php\?term=(.*)$/)[1]) rescue nil
      }
    end
    # we give a very high 'skip' because this will allow us to get the number of definitions by retrieving the previous definition
    uri = URI.parse("http://www.urbanwap.com/search.php?term=#{URI.escape words}&skip=65536")
    page = @bot.httputil.get(uri)
    if page.nil?
      m.reply "Couldn't retrieve an urban dictionary definition of #{words}"
      return
    end
    if page =~ / is undefined<\/card><\/wml>/
      m.reply "There is no urban dictionary definition of #{words}"
      return
    end
    if page =~ /&amp;skip=(\d+)">prev<\/a>/
      numdefs = $1.to_i + 1
    else
      numdefs = 1
    end
    n = numdefs + n + 1 if n < 0
    if n > numdefs
      m.reply "Urban dictionary only has #{numdefs} definitions for '#{words}'"
      n = numdefs
    end
    if n < numdefs
      uri = URI.parse("http://www.urbanwap.com/search.php?term=#{URI.escape words}&skip=#{n-1}")
      page = @bot.httputil.get(uri)
      if page.nil?
        case n % 10
        when 1
          ord = 'st'
        when 2
          ord = 'nd'
        when 3
          ord = 'rd'
        else
          ord = 'th'
        end
        m.reply "Couldn't retrieve the #{n}#{ord} urban dictionary definition of #{words}"
        return
      end
    end
    m.reply "#{get_def(page)} (#{n}/#{numdefs})"
  end

  def get_def(text)
    # Start by removing the prev/home/next links
    t = text.gsub(/(?:<a href.*?>prev<\/a> )?<a href.*?>home<\/a>(?: <a href.*?>next<\/a>)?/,'')
    # Close up paragraphs
    t.gsub!(/<\/?p>/, ' ')
    t.gsub!("\n", ' ')
    # Reverse headings
    t.gsub!(/<\/?b>/,"#{Reverse}")
    # Enbolden links
    t.gsub!(/<\/?a(?: .*?)?>/,"#{Bold}")
    # Reverse examples
    t.gsub!(/<\/?(?:i|em)>/,"#{Underline}")
    # Clear anything else
    t.gsub!(/<.*?>/, '')

    Utils.decode_html_entities t.strip
  end

  def uotd(m, params)
    home = @bot.httputil.get("http://www.urbanwap.com/")
    if home.nil?
      m.reply "Couldn't get the urban dictionary word of the day"
      return
    end
    home.match(/Word of the Day: <a href="(.*?)">.*?<\/a>/)
    wotd = $1
    debug "Urban word of the day: #{wotd}"
    page = @bot.httputil.get(wotd)
    if page.nil?
      m.reply "Couldn't get the urban dictionary word of the day"
    else
      m.reply get_def(page)
    end
  end
end

plugin = UrbanPlugin.new
plugin.map "urban *words :n", :requirements => { :n => /^-?\d+$/ }, :action => 'urban'
plugin.map "urban [*words]", :action => 'urban'
plugin.map "urbanday", :action => 'uotd'

