require 'uri/common'
require 'cgi'

FACTMAP = { "mrt" => "Mr\. T",
            "vin" => "Vin Diesel",
            "chuck" => "Chuck Norris" }

class ChuckNorrisPlugin < Plugin

  def help(plugin, topic="")
    "getfact => show a random Chuck Norris or Vin Diesel or Mr. T fact || chucknorris => show a random Chuck Norris quote || vindiesel => show a random Vin Diesel quote || mrt => I pity the foo who can't figure this one out."
  end
  
  def getfact(m, params)
    who = params[:who]
    m.reply "Errorn!!!" unless who
    
    if who == 'random'
        who = FACTMAP.keys[rand(FACTMAP.length)]
    end
    
    longwho = FACTMAP[who]
    unless longwho
        m.reply "Who the crap is #{who}?!?!"
        return
    end
    
    matcher = %r{<h1> And now a random fact about #{longwho}...</h1>(.+?)<hr />}
      
    factdata = @bot.httputil.get(URI.parse("http://www.4q.cc/index.php?pid=fact&person=#{who}"))
    unless factdata
      m.reply "This #{longwho} fact punched my teeth in. (HTTP error)"
    end

    if factdata =~ matcher
      m.reply(CGI::unescapeHTML($1))
    else
      m.reply "This #{longwho} fact made my brain explode. (Parse error)"
    end

  end

end

plugin = ChuckNorrisPlugin.new
plugin.map 'getfact :who', :action => 'getfact',
                          :defaults => {:who => 'random'}
plugin.map 'chucknorris :who', :action => 'getfact', :defaults => {:who => "chuck"}
plugin.map 'mrt :who', :action => 'getfact', :defaults => {:who => "mrt"}
plugin.map 'vindiesel :who', :action => 'getfact', :defaults => {:who => "vin"}
