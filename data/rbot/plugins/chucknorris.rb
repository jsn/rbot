require 'uri/common'
require 'cgi'

class ChuckNorrisPlugin < Plugin

  def help(plugin, topic="")
    "chucknorris => show a random chuck norris fact."
  end
  
  def chucknorris(m, params)
    factdata = @bot.httputil.get(URI.parse('http://www.4q.cc/index.php?pid=fact&person=chuck'))
    unless factdata
      m.reply "This Chuck Norris fact made my brain explode. (HTTP error)"
      return
    end


    if factdata =~ %r{<h1> And now a random fact about Chuck Norris...</h1>(.+?)<hr />}
      m.reply(CGI::unescapeHTML($1))
    else
      m.reply "This Chuck Norris fact punched my teeth in. (Parse error)"
    end

  end

end

plugin = ChuckNorrisPlugin.new
plugin.map 'chucknorris'
