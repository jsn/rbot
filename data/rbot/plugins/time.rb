#-- vim:sw=2:et
#++
#
# :title: Time Zone Plugin for rbot
#
# Author:: Ian Monroe <ian@monroe.nu>
# Copyright:: (C) 2006 Ian Monroe
# License:: MIT license

require 'tzinfo'

class TimePlugin < Plugin

  def help(plugin, topic="")
  "time <time zone> to get the local time of a certain location. <time zone> can be <Continent/City> or <two character country code>. time <nick> to see the local time of that person if their time zone is set. time admin set <nick> <time zone> to set the time zone for another user. time [admin] reset [nick] to let the bot forget about the tzinfo about someone"
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
    
    TZInfo::Timezone.get( zone ).now
  end

  def showTime(m, params)
    zone = params[:where].join('_')
    if params[:where].size > 0 then
      begin
        m.reply "#{zone} - #{getTime( m,  zone )}"
      rescue TZInfo::InvalidTimezoneIdentifier
        if @registry.has_key?( zone ) then
          zone =  @registry[ zone ]
          m.reply "#{zone} - #{getTime( m,  zone )}"
        else
          m.reply "#{zone} is an unknown time."
        end
      end
    else
      if @registry.has_key?( m.sourcenick) then
        zone = @registry[ m.sourcenick ]
        m.reply "#{m.sourcenick}: #{zone} - #{getTime( m,  zone )}"
      else
        m.reply "#{m.sourcenick}: use time set <Continent/City> to set your timezone."
      end
    end
  end

  def setUserZone( m, params )
    if params[:where].size > 0 then
      s = setZone( m, m.sourcenick, params[:where].join('_') )
    else
      m.reply "Requires Continent/City or country code"
    end
  end

  def resetUserZone( m, params )
    s = resetZone( m, m.sourcenick)
  end

  def setAdminZone( m, params )
    if params[:who] and params[:where].size > 0 then
      s = setZone( m, params[:who], params[:where].join('_') )
    else
      m.reply "Requires a nick and the Continent/City or country code"
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
      m.reply "#{zone} is an invalid timezone. Format is Continent/City or a two character country code."
      return
    end
    @registry[ user ] = zone
    m.reply "Ok, I'll remember that #{user} is on the #{zone} timezone"
  end

  def resetZone( m, user )
    @registry.delete(user)
    m.reply "Ok, I've forgotten #{user}'s timezone"
  end
end

plugin = TimePlugin.new

plugin.default_auth('admin', false)

plugin.map 'time set [time][zone] [to] *where', :action=> 'setUserZone', :defaults => {:where => false}
plugin.map 'time reset [time][zone]', :action=> 'resetUserZone'
plugin.map 'time admin set [time][zone] [for] :who [to] *where', :action=> 'setAdminZone', :defaults => {:who => false, :where => false}
plugin.map 'time admin reset [time][zone] [for] :who', :action=> 'resetAdminZone', :defaults => {:who => false}
plugin.map 'time *where', :action => 'showTime', :defaults => {:where => false}
