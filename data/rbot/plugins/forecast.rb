#-- vim:sw=2:et
#++
#
# :title: Forecast plugin for rbot
#
# Author:: MrChucho (mrchucho@mrchucho.net)
# Copyright:: (C) 2006 Ralph M. Churchill

require 'soap/wsdlDriver'
# TODO why not use HttpUtil instead of open-uri?
require 'open-uri'
require 'rexml/document'
require 'erb'


class LatLong
    include ERB::Util
    # Determine the latitude and longitude of a location. City, State and/or ZIP
    # are all valid.
    # [+return+] latitude,longitude
    def get_lat_long(loc)
        loc = url_encode(loc)
        url="http://api.local.yahoo.com/MapsService/V1/geocode?appid=mrchucho_rbot_weather&location=#{loc}"
        lat,long = 0,0
        begin
            open(url) do |xmldoc|
                results = (REXML::Document.new xmldoc).root
                lat = results.elements["//Latitude/text()"].to_s
                long = results.elements["//Longitude/text()"].to_s
            end
        rescue => err
            raise err #?
        end
        return lat.to_f,long.to_f
    end
end

class Forecast
    WSDL_URI="http://www.nws.noaa.gov/forecasts/xml/SOAP_server/ndfdXMLserver.php?wsdl"
    def initialize(lat,long)
        @lat,@long=lat,long
        # this extra step is for backward/forward compatibility
        factory = SOAP::WSDLDriverFactory.new(WSDL_URI)
        @forecaster=factory.respond_to?(:create_rpc_driver) ?
            factory.create_rpc_driver : factory.create_driver
    end
    def forecast
        return parse(retrieve),Time.new
    end
private
    def retrieve
        forecast = @forecaster.NDFDgenByDay(
            @lat,@long,Time.now.strftime("%Y-%m-%d"),2,"24 hourly")
        (REXML::Document.new(forecast)).root
    end
    def parse(xml)
        msg = String.new
        (1..2).each do |day|
            d  = (day==1) ? 'Today' : 'Tomorrow'
            hi = xml.elements["//temperature[@type='maximum']/value[#{day}]/text()"]
            lo = xml.elements["//temperature[@type='minimum']/value[#{day}]/text()"]
            w  = xml.elements["//weather/weather-conditions[#{day}]/@weather-summary"]
            precip_am = xml.elements["//probability-of-precipitation/value[#{day*2-1}]/text()"]
            precip_pm = xml.elements["//probability-of-precipitation/value[#{day*2}]/text()"]
            msg += "#{d}: Hi #{hi} Lo #{lo}, #{w}. Precip: AM #{precip_am}% PM #{precip_pm}%\n"
        end
        msg
    end
end

class ForecastPlugin < Plugin
    USAGE='forecast <location> => show the 2-day forecast for a location. Location can be any combination of City, State, Country and ZIP'
    def help(plugin,topic="")
        USAGE
    end
    def usage(m,params={})
        m.reply USAGE
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
        @forecast_cache = Hash.new
        @cache_mutex = Mutex.new
    end

    def forecast(m,params)
        if params[:location] and params[:location].any?
            loc = params[:location].join
            @registry[m.sourcenick] = loc
            get_forecast(m,loc)
        else
            if @registry.has_key?(m.sourcenick) then
                loc = @registry[m.sourcenick]
                get_forecast(m,loc)
            else
                m.reply "Please specifiy the City, State or ZIP"
            end
        end
    end

    def get_forecast(m,loc)
      begin
        @cache_mutex.synchronize do
          if @forecast_cache.has_key?(loc) and
            Time.new - @forecast_cache[loc][:date] < 3600
            forecast = @forecast_cache[loc][:forecast]
            if forecast
              m.reply forecast
              return
            end
          end
        end
        begin
          l = LatLong.new
          f = Forecast.new(*l.get_lat_long(loc))
          forecast,forecast_date = f.forecast
        rescue => err
          m.reply err
        end
        if forecast
          m.reply forecast
          @cache_mutex.synchronize do
            @forecast_cache[loc] = {
              :forecast => forecast,
              :date => forecast_date
            }
          end
        else
          m.reply "Couldn't find forecast for #{loc}"
        end
      rescue => e
        m.reply "ERROR: #{e}"
      end
    end
end
plugin = ForecastPlugin.new
plugin.map 'forecast *location',
  :defaults => {:location => false}, :thread => true
