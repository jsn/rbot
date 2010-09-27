#-- vim:sw=2:et
#++
#
# :title: Time Zone Plugin for rbot
#
# Author:: Ian Monroe <ian@monroe.nu>
# Author:: Raine Virta <raine.virta@gmail.com>
# Copyright:: (C) 2006 Ian Monroe
# Copyright:: (C) 2010 Raine Virta
# License:: MIT license

require 'tzinfo'

class TimePlugin < Plugin
  def help(plugin, topic="")
    case topic
    when "set"
      _("usage: time set <Continent>/<City> -- setting your location allows the bot to calibrate time replies into your time zone, and other people to figure out what time it is for you")
    else
      _("usage: time <timestamp|time zone|nick> -- %{b}timestamp%{b}: get info about a specific time, relative to your own time zone | %{b}time zone%{b}: get local time of a certain location, <time zone> can be '<Continent>/<City>' or a two character country code | %{b}nick%{b}: get local time of another person, given they have set their location | see `%{prefix}help time set` on how to set your location") % {
        :b => Bold,
        :prefix => @bot.config['core.address_prefix'].first
      }
    end
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
  end

  def getTime(m, zone )
    if zone.length == 2 then #country code
      zone.upcase!
      zone = 'GB' if zone == 'UK' #country doesn't know its own name
      begin
        nationZones = TZInfo::Country.get(zone).zone_identifiers
        if nationZones.size == 1 then
          zone = nationZones[0]
        else
          m.reply "#{zone} has the cities of #{nationZones.join( ', ' )}."
        end
      rescue TZInfo::InvalidCountryCode
        m.reply "#{zone} is not a valid country code."
      end
    end
    ['/', '_'].each { |sp|
        arr = Array.new
        zone.split(sp).each{ |s|
            s[0] = s[0,1].upcase
            s[1, s.length] = s[1, s.length].downcase if sp == '/'
            arr.push(s) }
            zone = arr.join( sp )
        }

    tz = TZInfo::Timezone.get( zone )
    "#{tz.friendly_identifier} - #{tz.now.strftime( '%a %b %d %H:%M' )} #{tz.current_period.abbreviation}"
  end

  def showTime(m, params)
    zone = params[:where].join('_')
    if params[:where].size > 0 then
      begin
        m.reply getTime( m,  zone )
      rescue TZInfo::InvalidTimezoneIdentifier
        if @registry.has_key?( zone ) then
          zone =  @registry[ zone ]
          m.reply getTime( m,  zone )
        else
          parse(m, params)
        end
      end
    else
      if @registry.has_key?( m.sourcenick) then
        zone = @registry[ m.sourcenick ]
        m.reply "#{m.sourcenick}: #{getTime( m,  zone )}"
      else
        m.reply "#{m.sourcenick}: use time set <Continent>/<City> to set your time zone."
      end
    end
  end

  def setUserZone( m, params )
    if params[:where].size > 0 then
      s = setZone( m, m.sourcenick, params[:where].join('_') )
    else
      m.reply "Requires <Continent>/<City> or country code"
    end
  end

  def resetUserZone( m, params )
    s = resetZone( m, m.sourcenick)
  end

  def setAdminZone( m, params )
    if params[:who] and params[:where].size > 0 then
      s = setZone( m, params[:who], params[:where].join('_') )
    else
      m.reply "Requires a nick and the <Continent>/<City> or country code"
    end
  end

  def resetAdminZone( m, params )
    if params[:who]
      s = resetZone( m, params[:who])
    else
      m.reply "Requires a nick"
    end
  end

  def setZone( m, user, zone )
    begin
      getTime( m,  zone )
    rescue TZInfo::InvalidTimezoneIdentifier
      m.reply "#{zone} is an invalid time zone. Format is <Continent>/<City> or a two character country code."
      return
    end
    @registry[ user ] = zone
    m.reply "Ok, I'll remember that #{user} is on the #{zone} time zone"
  end

  def resetZone( m, user )
    @registry.delete(user)
    m.reply "Ok, I've forgotten #{user}'s time zone"
  end

  def parse(m, params)
    require 'time'
    str = params[:where].to_s
    now = Time.now

    begin
      time = begin
        if zone = @registry[m.sourcenick]
          on_timezone(zone) {
            Time.parse str
          }
        else
          Time.parse str
        end
      rescue ArgumentError => e
        # Handle 28/9/1978, which is a valid date representation at least in Italy
        if e.message == 'argument out of range'
          str.tr!('/', '-')
          Time.parse str
        else
          raise
        end
      end

      offset = (time - now).abs
      raise if offset < 0.1
    rescue => e
      if str.match(/^\d+$/)
        time = Time.at(str.to_i)
      else
        m.reply _("unintelligible time")
        return
      end
    end

    if zone = @registry[m.sourcenick]
      time = time.convert_zone(zone)
    end

    m.reply _("%{time} %{w} %{str}") % {
      :time => time.strftime(_("%a, %d %b %Y %H:%M:%S %Z %z")),
      :str  => Utils.timeago(time),
      :w    => time >= now ? _("is") : _("was")
    }
  end

  def on_timezone(to_zone)
    original_zone = ENV["TZ"]
    ENV["TZ"] = to_zone
    return yield
    ENV["TZ"] = original_zone
  end
end

class ::Time
  def convert_zone(to_zone)
    original_zone = ENV["TZ"]
    utc_time = dup.gmtime
    ENV["TZ"] = to_zone
    to_zone_time = utc_time.localtime
    ENV["TZ"] = original_zone
    return to_zone_time
  end
end

plugin = TimePlugin.new

plugin.default_auth('admin', false)

plugin.map 'time set [time][zone] [to] *where', :action=> 'setUserZone', :defaults => {:where => false}
plugin.map 'time reset [time][zone]', :action=> 'resetUserZone'
plugin.map 'time admin set [time][zone] [for] :who [to] *where', :action=> 'setAdminZone', :defaults => {:who => false, :where => false}
plugin.map 'time admin reset [time][zone] [for] :who', :action=> 'resetAdminZone', :defaults => {:who => false}
plugin.map 'time *where', :action => 'showTime', :defaults => {:where => false}
