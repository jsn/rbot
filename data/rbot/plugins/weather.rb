#
# Weather plugin for rbot
# by MrChucho (mrchucho@mrchucho.net)
# Copyright (C) 2006 Ralph M. Churchill
#
require 'open-uri'
require 'rexml/document'

class CurrentConditions
    def initialize(station)
        @station = station
        @url = "http://www.nws.noaa.gov/data/current_obs/#{@station.upcase}.xml"
        @etag = String.new
        @mtime = Time.mktime(0)
        @current_conditions = String.new
        @iscached = false
    end
    def update
        begin
            open(@url,"If-Modified-Since" => @mtime.rfc2822) do |feed|
            # open(@url,"If-None-Match"=>@etag) do |feed|
                @etag = feed.meta['etag']
                @mtime = feed.last_modified
                cc_doc = (REXML::Document.new feed).root
                @iscached = false
                @current_conditions = parse(cc_doc)
            end
        rescue OpenURI::HTTPError => e
            case e
            when /304/:
                @iscached = true
            when /404/:
                raise "Data for #{@station} not found"
            else
                raise "Error retrieving data: #{e}"
            end
        end
        @current_conditions # +" Cached? "+ ((@iscached) ? "Y" : "N")
    end
    def parse(cc_doc)
        cc = Hash.new
        cc_doc.elements.each do |c|
            cc[c.name.to_sym] = c.text
        end
        "At #{cc[:observation_time_rfc822]}, the wind was #{cc[:wind_string]} at #{cc[:location]} (#{cc[:station_id]}). The temperature was #{cc[:temperature_string]}#{heat_index_or_wind_chill(cc)}, and the pressure was #{cc[:pressure_string]}. The relative humidity was #{cc[:relative_humidity]}%. Current conditions are #{cc[:weather]} with #{cc[:visibility_mi]}mi visibility."
    end
private
    def heat_index_or_wind_chill(cc)
        hi = cc[:heat_index_string]
        wc = cc[:windchill_string]
        if hi != 'NA' then
            " with a heat index of #{hi}"
        elsif wc != 'NA' then
            " with a windchill of #{wc}"
        else
            ""
        end
    end
end

class MyWeatherPlugin < Plugin
  
  def help(plugin, topic="")
    "weather <STATION> => display the current conditions at the location specified by the STATION code [Lookup your STATION code at http://www.nws.noaa.gov/data/current_obs/ - this will also store the STATION against your nick, so you can later just say \"weather\", weather => display the current weather at the location you last asked for" 
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
    @cc_cache = Hash.new
  end
  
  def describe(m, where)
    if @cc_cache.has_key?(where) then
        met = @cc_cache[where]
    else
        met = CurrentConditions.new(where)
    end
    if met
      begin
        m.reply met.update
        @cc_cache[where] = met
      rescue => e
        m.reply e.message
      end
    else
      m.reply "couldn't find weather data for #{where}"
    end
  end

  def weather(m, params)
    if params[:where]
      @registry[m.sourcenick] = params[:where]
      describe(m,params[:where])
    else
      if @registry.has_key?(m.sourcenick)
        where = @registry[m.sourcenick]
        describe(m,where)
      else
        m.reply "I don't know where you are yet! Lookup your station at http://www.nws.noaa.gov/data/current_obs/ and tell me 'weather <station>', then I'll know."
      end
    end
  end
end

plugin = MyWeatherPlugin.new
plugin.map 'weather :where', :defaults => {:where => false}
