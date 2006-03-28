require 'yaml'

MIN_RATING = 6.0

FACTS_FILE =  File.join Config::datadir, "plugins", "chucknorris.yml"
puts "+ [chucknorris] Loading #{FACTS_FILE}..."
FACTS = YAML.load_file(FACTS_FILE).map{|k,v| [v,k]}
puts "+ [chucknorris] #{FACTS.length} Chuck Norris facts loaded..."
puts "Sample: #{FACTS[rand(FACTS.size)].inspect}"

# the plugin
class ChuckNorrisPlugin < Plugin

  def help(plugin, topic="chuck")
    "fact|chuck|norris|chucknorris [min_rating] => \"fact\" shows a random Chuck Norris fact (optional minimum rating from 1-10, default=6.0)."
    #\"fact [person]\" shows a fact about someone in the channel. 
  end

  def fact(m, params)
    min = params[:minrating].to_f
    puts "+ Getting Chuck Norris fact (rating > #{min})..."

    rating = -1000.0
    count = 0

    while rating < min
      count += 1

      rating, fact = FACTS[rand(FACTS.length)]

      if count > 1000
        puts "  - gave up searching"
        m.reply "Looks like I ain't finding a quote with a rating higher than #{min} any time today."
        return
      end

    end

    puts "  - got > #{min} fact in #{count} tries..."
    m.reply "#{fact} [score=#{rating}]"

  end

end

plugin = ChuckNorrisPlugin.new

plugin.map 'fact :minrating', :action => 'fact', :defaults => {:minrating=>MIN_RATING}
plugin.map 'chucknorris :minrating', :action => 'fact', :defaults => {:minrating=>MIN_RATING}
plugin.map 'chuck :minrating', :action => 'fact', :defaults => {:minrating=>MIN_RATING}
plugin.map 'norris :minrating', :action => 'fact', :defaults => {:minrating=>MIN_RATING}

