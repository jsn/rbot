require 'yaml'
require 'zlib'

MIN_RATING = 6.0
MIN_VOTES = 25

# the plugin
class ChuckNorrisPlugin < Plugin

  # Loadez les factes
  def initialize
    if path = find_facts_file('chucknorris.yml.gz')
      fyml = Zlib::GzipReader.open(path)
    elsif path = find_facts_File('chucknorris.yml')
      fyml = open(path)
    else
      raise "Error: Couldn't find chucknorris.yml[.gz]"
    end
    
    debug "+ [chucknorris] Loading #{path}..."
    
    @@facts = YAML.load(fyml).map{|fact,(score,votes)| votes >= MIN_VOTES ? [score,fact] : nil}.compact
    debug "+ [chucknorris] #{@@facts.length} Chuck Norris facts loaded..."
    debug "  Random fact: #{@@facts[rand(@@facts.size)].inspect}"
    
    super
  end

  def name
    "chucknorris"
  end
  
  # Just a little helper for the initialize method...
  def find_facts_file(name)
    full_path = File.join Config::datadir, "plugins", name
    found_files = Dir[full_path]
    if found_files.empty?
      nil
    else
      found_files[0]
    end
  end
  
  # HELP!
  def help(plugin, topic="chuck")
    "fact|chuck|norris|chucknorris [min_rating] => \"fact\" shows a random Chuck Norris fact (optional minimum rating from 1-10, default=6.0)."
    #\"fact [person]\" shows a fact about someone in the channel. 
  end

  # The meat.
  def fact(m, params)
    min = params[:minrating].to_f
    debug "+ Getting Chuck Norris fact (rating > #{min})..."

    viable_facts = @@facts.select {|rating, fact| rating >= min}
    if viable_facts.empty?
      debug "  - no facts found with rating >= #{min}"
      m.reply "Are you nuts?!? There are no facts better than #{min}!!!"
      return
    end

    rating, fact = viable_facts[rand(viable_facts.length)]
    m.reply "#{fact} [score=#{rating}]"
  end

end

plugin = ChuckNorrisPlugin.new

plugin.map 'fact :minrating', :action => 'fact', :defaults => {:minrating=>MIN_RATING}
plugin.map 'chucknorris :minrating', :action => 'fact', :defaults => {:minrating=>MIN_RATING}
plugin.map 'chuck :minrating', :action => 'fact', :defaults => {:minrating=>MIN_RATING}
plugin.map 'norris :minrating', :action => 'fact', :defaults => {:minrating=>MIN_RATING}

