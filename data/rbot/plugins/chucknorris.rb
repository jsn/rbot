require 'uri/common'
require 'cgi'

FACTMAP = { "mrt" => "Mr\. T",
            "vin" => "Vin Diesel",
            "chuck" => "Chuck Norris" }

class ChuckNorrisPlugin < Plugin

  def help(plugin, topic="")
    "getfact => show a random fact, or append someone's name to get a fact about that person (eg. !getfact epitron)|| chucknorris => show a random Chuck Norris quote || vindiesel => show a random Vin Diesel quote || mrt => I pity the foo who can't figure this one out."
  end
  
  def getfact(m, params)
    who = params[:who]
    valid_people = FACTMAP.keys + ["random"]
    
    # if the person wants a fact about themselves, then it'll substitute the name.
    if valid_people.include? who
      substitute_name = nil
    else
      substitute_name = who
      who = 'random'
    end
    
    # pick a random person
    if who == 'random'
      who = FACTMAP.keys[rand(FACTMAP.length)]
    end
    
    # get the long name
    longwho = FACTMAP[who]
    unless longwho
      m.reply "Who the crap is #{who}?!?!"
      return
    end
    
    matcher = %r{<h1> And now a random fact about #{longwho}...</h1>(.+?)<hr />}
      
    # get the fact
    factdata = @bot.httputil.get(URI.parse("http://www.4q.cc/index.php?pid=fact&person=#{who}"))
    unless factdata
      m.reply "This #{longwho} fact punched my teeth in. (HTTP error)"
    end

    # parse the fact
    if factdata =~ matcher
      fact = CGI::unescapeHTML($1)
      fact.gsub!(longwho, substitute_name) if substitute_name
      m.reply fact
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
