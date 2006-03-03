require 'uri/common'
require 'cgi'

# the 4q.cc "id => full name" mapping
FACTMAP = { "mrt" => "Mr\. T",
            "vin" => "Vin Diesel",
            "chuck" => "Chuck Norris" }

MIN_RATING = 6.0

PISSED_EXPRESSIONS = [
    "fuck this, i'm going to go get toed up.",
    "screw this, i'm going to get hammered.",
    "forget this, i'm going to iron some shirts.",
    "disregard this, i'm going out to kill me some prostitutes.",
]

# exceptions
class HTTPError < Exception; end
class ParseError < Exception; end

# the plugin
class ChuckNorrisPlugin < Plugin

  def help(plugin, topic="")
    "fact [person] => \"fact\" shows a random Chuck Norris, Vin Diesel, or Mr. T fact. \"fact [person]\" shows a fact about someone in the channel. || chucknorris, chuck, norris => random Chuck Norris fact || vindiesel, vin, diesel => random Vin Diesel fact || mrt => I pity the foo who can't figure this one out."
  end

  def getfact(who)
      raise "Unknown name: #{who}" unless FACTMAP.keys.include? who
      # get the fact
      factdata = @bot.httputil.get(URI.parse("http://www.4q.cc/index.php?pid=fact&person=#{who}"))
      unless factdata
        raise HTTPError
      end
    
      longwho = FACTMAP[who]

      # regexes
      fact_matcher = %r{<h1> And now a random fact about #{longwho}...</h1>(.+?)<hr />}
      rating_matcher = %r{Current Rating: <b>(\d+\.\d+)</b>}

      # parse the fact
      if factdata =~ fact_matcher
        fact = CGI::unescapeHTML($1)
        if factdata =~ rating_matcher
            rating = $1.to_f
            puts "fact=[#{fact}], rating=[#{rating}]"
            return [fact, rating]
        end
      end
        
      raise ParseError
    
  end

  def fact(m, params)
    who = params[:who]
    max_tries = (params[:tries] or "10").to_i
    
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
      if substitute_name
        # take out the Mr. T facts if you're inserting someone's name
        # beacuse tons of them suck, and most of them revolve around
        # "pitying" someone or something.
        people = FACTMAP.keys - ["mrt"]
        who = people[rand(people.length)]
      else
        who = FACTMAP.keys[rand(FACTMAP.length)]
      end
    end
    
    # get the long name
    longwho = FACTMAP[who]
    unless longwho
      m.reply "Who the crap is #{who}?!?!"
      return
    end
    
    # get the fact

    m.reply "alright, let's see if I can find a good one..."

    tries = 0
    results = []
    loop do
        
        begin
        
            puts "[chucknorris] Try number #{tries}/#{max_tries}..."

            tries += 1
            fact, rating = getfact(who)
            
            if rating >= MIN_RATING
                fact.gsub!(longwho, substitute_name) if substitute_name
                m.reply "#{results.join(', ') + "... "}hrm, this one's not bad:"
                m.reply "#{fact} [rating: #{rating}]"
                return
            else
                results << "lame"
            end
    
            if tries > max_tries
                m.reply "#{results.join(', ')}... these all suck. #{PISSED_EXPRESSIONS[rand(PISSED_EXPRESSIONS.length)]}"
                return
            end
            
        rescue HTTPError
          #m.reply "This #{longwho} fact punched my teeth in. (HTTP error)"
          results << "DOH!"
          tries += 1
        rescue ParseError
          #m.reply "This #{longwho} fact made my brain explode. (Parse error)"
          results << "wtf?"
          tries += 1
        end
      
    end
  
  end


end

plugin = ChuckNorrisPlugin.new

plugin.map 'fact :who :tries', :action => 'fact',
                          :defaults => {:who => 'random', :tries=>10}

plugin.map 'chucknorris :who', :action => 'fact', :defaults => {:who => "chuck"}
plugin.map 'chuck :who', :action => 'fact', :defaults => {:who => "chuck"}
plugin.map 'norris :who', :action => 'fact', :defaults => {:who => "chuck"}

plugin.map 'vindiesel :who', :action => 'fact', :defaults => {:who => "vin"}
plugin.map 'diesel :who', :action => 'fact', :defaults => {:who => "vin"}
plugin.map 'vin :who', :action => 'fact', :defaults => {:who => "vin"}

plugin.map 'mrt :who', :action => 'fact', :defaults => {:who => "mrt"}

