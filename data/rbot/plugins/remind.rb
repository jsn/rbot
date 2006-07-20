require 'rbot/utils'

class RemindPlugin < Plugin
  # read a time in string format, turn it into "seconds from now".
  # example formats handled are "5 minutes", "2 days", "five hours",
  # "11:30", "15:45:11", "one day", etc.
  #
  # Throws:: RunTimeError "invalid time string" on parse failure
  def timestr_offset(timestr)
    case timestr
      when (/^(\S+)\s+(\S+)$/)
        mult = $1
        unit = $2
        if(mult =~ /^([\d.]+)$/)
          num = $1.to_f
          raise "invalid time string" unless num
        else
          case mult
            when(/^(one|an|a)$/)
              num = 1
            when(/^two$/)
              num = 2
            when(/^three$/)
              num = 3
            when(/^four$/)
              num = 4
            when(/^five$/)
              num = 5
            when(/^six$/)
              num = 6
            when(/^seven$/)
              num = 7
            when(/^eight$/)
              num = 8
            when(/^nine$/)
              num = 9
            when(/^ten$/)
              num = 10
            when(/^fifteen$/)
              num = 15
            when(/^twenty$/)
              num = 20
            when(/^thirty$/)
              num = 30
            when(/^sixty$/)
              num = 60
            else
              raise "invalid time string"
          end
        end
        case unit
          when (/^(s|sec(ond)?s?)$/)
            return num
          when (/^(m|min(ute)?s?)$/)
            return num * 60
          when (/^(h|h(ou)?rs?)$/)
            return num * 60 * 60
          when (/^(d|days?)$/)
            return num * 60 * 60 * 24
          else
            raise "invalid time string"
        end
      when (/^(\d+):(\d+):(\d+)$/)
        hour = $1.to_i
        min = $2.to_i
        sec = $3.to_i
        now = Time.now
        later = Time.mktime(now.year, now.month, now.day, hour, min, sec)
        return later - now
      when (/^(\d+):(\d+)$/)
        hour = $1.to_i
        min = $2.to_i
        now = Time.now
        later = Time.mktime(now.year, now.month, now.day, hour, min, now.sec)
        return later - now
      when (/^(\d+):(\d+)(am|pm)$/)
        hour = $1.to_i
        min = $2.to_i
        ampm = $3
        if ampm == "pm"
          hour += 12
        end
        now = Time.now
        later = Time.mktime(now.year, now.month, now.day, hour, min, now.sec)
        return later - now
      when (/^(\S+)$/)
        num = 1
        unit = $1
        case unit
          when (/^(s|sec(ond)?s?)$/)
            return num
          when (/^(m|min(ute)?s?)$/)
            return num * 60
          when (/^(h|h(ou)?rs?)$/)
            return num * 60 * 60
          when (/^(d|days?)$/)
            return num * 60 * 60 * 24
          else
            raise "invalid time string"
        end
      else
        raise "invalid time string"
    end
  end

  def initialize
    super
    @reminders = Hash.new
  end
  def cleanup
    @reminders.each_value {|v|
      v.each_value {|vv|
        @bot.timer.remove(vv)
      }
    }
    @reminders.clear
  end
  def help(plugin, topic="")
    "reminder plugin: remind <who> [about] <message> in <time>, remind <who> [about] <message> every <time>, remind <who> [about] <message> at <time>, remind <who> no more [about] <message>, remind <who> no more. Generally <who> should be 'me', but you can remind others (nick or channel) if you have remind_others auth"
  end
  def add_reminder(who, subject, timestr, repeat=false)
    begin
      period = timestr_offset(timestr)
    rescue RuntimeError
      return "couldn't parse that time string (#{timestr}) :("
    end
    if(period <= 0)
      return "that time is in the past! (#{timestr})"
    end
    if(period < 30 && repeat)
      return "repeats of less than 30 seconds are forbidden"
    end
    if(!@reminders.has_key?(who))
      @reminders[who] = Hash.new
    elsif(@reminders[who].has_key?(subject))
      del_reminder(who, subject)
    end

    if(repeat)
      @reminders[who][subject] = @bot.timer.add(period) {
        time = Time.now + period
        tstr = time.strftime("%H:%M:%S")
        @bot.say who, "repeat reminder (next at #{tstr}): #{subject}"
      }
    else
      @reminders[who][subject] = @bot.timer.add_once(period) {
        time = Time.now + period
        tstr = time.strftime("%H:%M:%S")
        @bot.say who, "reminder (#{tstr}): #{subject}"
      }
    end
    return false
  end
  def del_reminder(who, subject=nil)
    if(subject)
      if(@reminders.has_key?(who) && @reminders[who].has_key?(subject))
        @bot.timer.remove(@reminders[who][subject])
        @reminders[who].delete(subject)
        return true
      else
        return false
      end
    else
      if(@reminders.has_key?(who))
        @reminders[who].each_value {|v|
          @bot.timer.remove(v)
        }
        @reminders.delete(who)
        return true
      else
        return false
      end
    end
  end
  def remind(m, params)
    who = params.has_key?(:who) ? params[:who] : m.sourcenick
    string = params[:string].to_s
    debug "in remind, string is: #{string}"
    if(string =~ /^(.*)\s+in\s+(.*)$/)
      subject = $1
      period = $2
      if(err = add_reminder(who, subject, period))
        m.reply "incorrect usage: " + err
        return
      end
    elsif(string =~ /^(.*)\s+every\s+(.*)$/)
      subject = $1
      period = $2
      if(err = add_reminder(who, subject, period, true))
        m.reply "incorrect usage: " + err
        return
      end
    elsif(string =~ /^(.*)\s+at\s+(.*)$/)
      subject = $1
      time = $2
      if(err = add_reminder(who, subject, time))
        m.reply "incorrect usage: " + err
        return
      end
    else
      usage(m)
      return
    end
    m.okay
  end
  def no_more(m, params)
    who = params.has_key?(:who) ? params[:who] : m.sourcenick
    deleted = params.has_key?(:string) ? 
              del_reminder(who, params[:string].to_s) : del_reminder(who)
    if deleted
      m.okay
    else 
      m.reply "but I wasn't going to :/"
    end
  end
end
plugin = RemindPlugin.new
plugin.map 'remind me no more', :action => 'no_more'
plugin.map 'remind me no more about *string', :action => 'no_more'
plugin.map 'remind me no more *string', :action => 'no_more'
plugin.map 'remind me about *string'
plugin.map 'remind me *string'
plugin.map 'remind :who no more', :auth => 'remind_other', :action => 'no_more'
plugin.map 'remind :who no more about *string', :auth => 'remind_other', :action => 'no_more'
plugin.map 'remind :who no more *string', :auth => 'remind_other', :action => 'no_more'
plugin.map 'remind :who about *string', :auth => 'remind_other'
plugin.map 'remind :who *string', :auth => 'remind_other'

