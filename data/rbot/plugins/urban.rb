require 'cgi'
begin
  require 'rubyful_soup'
rescue
  warning "could not load rubyful_soup, urban dictionary disabled"
  warning "please get it from http://www.crummy.com/software/RubyfulSoup/"
  warning "or install it via gem"
  return
end
require 'uri/common'

class UrbanPlugin < Plugin

  def help( plugin, topic="")
    "urban [word] [n]. Give the [n]th definition of [word] from urbandictionary.com."
  end

  def privmsg( m )
    definitionN = 0

    if m.params
      paramArray = m.params.split(' ')
      if paramArray.last.to_i != 0 
        definitionN = paramArray.last.to_i - 1
        query = m.params.chomp( paramArray.last )
        query.rstrip!
      else
        query = m.params
      end
      uri = URI.parse( "http://www.urbandictionary.com/define.php?term=#{ URI.escape query}" )
    else 
      uri = URI.parse( "http://www.urbandictionary.com/random.php" )
    end

    soup = BeautifulSoup.new( @bot.httputil.get_cached( uri ) )
    if titleNavi = soup.find_all( 'td', :attrs => { 'class' => 'def_word' } )[0] then
      title = titleNavi.contents
      results = soup.find_all( 'div', :attrs => { 'class' => 'def_p' } )
      # debug PP.pp(results,'')
      output = Array.new
      if results[definitionN] then
        results[definitionN].p.contents.each { |s| output.push( strip_tags( s.to_s ) ) }
        m.reply "\002#{title}\002 - #{output} (#{definitionN+1}/#{results.length})"
      else
        m.reply "#{query} does not have #{definitionN + 1} definitions."
      end
    else
      m.reply "#{m.params} not found."
    end
  end

  def strip_tags(html)
    html.gsub(/<.+?>/,'').
    gsub(/&amp;/,'&').
    gsub(/&quot;/,'"').
    gsub(/&lt;/,'<').
    gsub(/&gt;/,'>').
    gsub(/&ellip;/,'...').
    gsub(/&apos;/, "'").
    gsub("\n",'')
  end
end

plugin = UrbanPlugin.new
plugin.register( "urban" )
