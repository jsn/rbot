require 'rbot/utils'

class RemindPlugin < Plugin
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
    if(plugin =~ /^remind\+$/)
      "see remind. remind+ can be used to remind someone else of something, using <nick> instead of 'me'. However this will generally require a higher auth level than remind."
    else
      "remind me [about] <message> in <time>, remind me [about] <message> every <time>, remind me [about] <message> at <time>, remind me no more [about] <message>, remind me no more"
    end
  end
  def add_reminder(who, subject, timestr, repeat=false)
    begin
      period = Irc::Utils.timestr_offset(timestr)
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
      end
    else
      if(@reminders.has_key?(who))
        @reminders[who].each_value {|v|
          @bot.timer.remove(v)
        }
        @reminders.delete(who)
      end
    end
  end
  def privmsg(m)

    if(m.params =~ /^(\S+)\s+(?:about\s+)?(.*)\s+in\s+(.*)$/)
      who = $1
      subject = $2
      period = $3
      if(who =~ /^me$/)
        who = m.sourcenick
      else
        unless(m.plugin =~ /^remind\+$/)
          m.reply "incorrect usage: use remind+ to remind persons other than yourself"
          return
        end
      end
      if(err = add_reminder(who, subject, period))
        m.reply "incorrect usage: " + err
        return
      end
    elsif(m.params =~ /^(\S+)\s+(?:about\s+)?(.*)\s+every\s+(.*)$/)
      who = $1
      subject = $2
      period = $3
      if(who =~ /^me$/)
        who = m.sourcenick
      else
        unless(m.plugin =~ /^remind\+$/)
          m.reply "incorrect usage: use remind+ to remind persons other than yourself"
          return
        end
      end
      if(err = add_reminder(who, subject, period, true))
        m.reply "incorrect usage: " + err
        return
      end
    elsif(m.params =~ /^(\S+)\s+(?:about\s+)?(.*)\s+at\s+(.*)$/)
      who = $1
      subject = $2
      time = $3
      if(who =~ /^me$/)
        who = m.sourcenick
      else
        unless(m.plugin =~ /^remind\+$/)
          m.reply "incorrect usage: use remind+ to remind persons other than yourself"
          return
        end
      end
      if(err = add_reminder(who, subject, time))
        m.reply "incorrect usage: " + err
        return
      end
    elsif(m.params =~ /^(\S+)\s+no\s+more\s+(?:about\s+)?(.*)$/)
      who = $1
      subject = $2
      if(who =~ /^me$/)
        who = m.sourcenick
      else
        unless(m.plugin =~ /^remind\+$/)
          m.reply "incorrect usage: use remind+ to remind persons other than yourself"
          return
        end
      end
      del_reminder(who, subject)
    elsif(m.params =~ /^(\S+)\s+no\s+more$/)
      who = $1
      if(who =~ /^me$/)
        who = m.sourcenick
      else
        unless(m.plugin =~ /^remind\+$/)
          m.reply "incorrect usage: use remind+ to remind persons other than yourself"
          return
        end
      end
      del_reminder(who)
    else
      m.reply "incorrect usage: " + help(m.plugin)
      return
    end
    m.okay
  end
end
plugin = RemindPlugin.new
plugin.register("remind")
plugin.register("remind+")

