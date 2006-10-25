# Weather plugin for rbot
# Copyright (C) 2006 Giuseppe Bilotta
#
# Author: Giuseppe "Oblomov" Bilotta <giuseppe.bilotta@gmail.com>

require 'uri'

class WuWeatherPlugin < Plugin
  
  def help(plugin, topic="")
    "weather <location> => display the current conditions at the location specified; you can use 'station <code>' to look up data by station code ( lookup your station code at http://www.weatherunderground.com/ )" 
  end
  
  def initialize
    super
    @url="http://mobile.wunderground.com/cgi-bin/findweather/getForecast?brand=mobile&query=%s"
    @station_url="http://mobile.wunderground.com/global/stations/%s.html"
  end

  def station(m, params)
    where = params[:where]
    begin
      unless where
        m.reply "I don't know where you are, #{m.sourcenick} (and you can't set it yet)"
      end
      xml = @bot.httputil.get_cached(@station_url % URI.escape(where))
      case xml
      when nil
        m.reply "couldn't retrieve weather information, sorry"
        return
      when /<table border.*?>(.*?)<\/table>/m
        data = $1
        m.reply weather_filter(data)
      else
        debug xml
        m.reply "something went wrong with the data for #{where}..."
      end
    rescue => e
      m.reply "retrieving info about '#{where}' failed (#{e})"
    end
  end

  def weather(m, params)
    where = params[:where].to_s
    begin
      if where.empty?
        m.reply "I don't know where you are, #{m.sourcenick} (and you can't set it yet)"
      end
      xml = @bot.httputil.get_cached(@url % URI.escape(where))
      case xml
      when nil
        m.reply "couldn't retrieve weather information, sorry"
        return
      when /City Not Found/
        m.reply "no such location found (#{where})"
        return
      when /<table border.*?>(.*?)<\/table>/m
        data = $1
        m.reply weather_filter(data)
      when /<a href="\/global\/stations\//
        stations = xml.scan(/<a href="\/global\/stations\/(.*?)\.html">/)
        m.reply "multiple stations available, use 'weather station <code>' where code is one of " + stations.join(", ")
      else
        debug xml
        m.reply "something went wrong with the data from #{where}..."
      end
    rescue => e
      m.reply "retrieving info about '#{where}' failed (#{e})"
    end
  end

  def weather_filter(stuff)
    txt = stuff
    txt.gsub!(/[\n\s]+/,' ')
    data = Hash.new
    txt.gsub!(/&nbsp;/, ' ')
    txt.gsub!(/&#176;/, ' ') # degree sign
    txt.gsub!(/<\/?b>/,'')
    txt.gsub!(/<\/?span[^<>]*?>/,'')
    txt.gsub!(/<img\s*[^<>]*?>/,'')
    txt.gsub!(/<br\s?\/?>/,'')

    result = Array.new
    if txt.match(/<\/a>\s*Updated:\s*(.*?)\s*Observed at\s*(.*?)\s*<\/td>/)
      result << ("Weather info for %s (updated on %s)" % [$2, $1])
    end
    txt.scan(/<tr>\s*<td>\s*(.*?)\s*<\/td>\s*<td>\s*(.*?)\s*<\/td>\s*<\/tr>/) { |k, v|
      unless v.empty? or v == "-" or k =="Raw METAR"
        result << ("%s: %s" % [k, v])
      end
    }
    return result.join('; ')
  end

end

plugin = WuWeatherPlugin.new
plugin.map 'weather station :where', :action => 'station', :defaults => {:where => false}
plugin.map 'weather *where', :defaults => {:where => false}

