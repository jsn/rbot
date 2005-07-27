class WeatherPlugin < Plugin
  
  def help(plugin, topic="")
    "weather <ICAO> => display the current weather at the location specified by the ICAO code [Lookup your ICAO code at http://www.nws.noaa.gov/oso/siteloc.shtml] - this will also store the ICAO against your nick, so you can later just say \"weather\", weather => display the current weather at the location you last asked for"
  end
  
  def initialize
    super
    # this plugin only wants to store strings
    class << @registry
      def store(val)
        val
      end
      def restore(val)
        val
      end
    end
    @metar_cache = Hash.new
  end
  
  def describe(m, where)
    if @metar_cache.has_key?(where) &&
       Time.now - @metar_cache[where].date < 3600
      met = @metar_cache[where]
    else
      met = Utils.get_metar(where)
    end
    
    if met
      m.reply met.pretty_print
      @metar_cache[where] = met
    else
      m.reply "couldn't find weather data for #{where}"
    end
  end
  
  def privmsg(m)
    case m.params
    when nil
      if @registry.has_key?(m.sourcenick)
        where = @registry[m.sourcenick]
        describe(m,where)
      else
        m.reply "I don't know where #{m.sourcenick} is!"
      end
    when (/^(\S{4})$/)
      where = $1
      @registry[m.sourcenick] = where
      describe(m,where)
    end
  end
  
end
plugin = WeatherPlugin.new
plugin.register("weather")
