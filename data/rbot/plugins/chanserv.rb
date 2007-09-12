#-- vim:sw=2:et
#++
#
# :title: Chanserv management plugin for rbot
#
# Author:: Giuseppe "Oblomov" Bilotta <giuseppe.bilotta@gmail.com>
#
# Copyright:: (C) 2006-2007 Giuseppe Bilotta
#
# ChanServ interface functionality.
#
# Currently, it only uses Chanserv to automatically op/hop/voice itself or others on channels where it can.
#
# TODO:: improve documentation, it really sucks as of now

class ChanServPlugin < Plugin

  Config.register Config::StringValue.new('chanserv.name',
    :default => "chanserv", :requires_restart => false,
    :desc => "Name of the chan server (all lowercase)")

  def help(plugin, topic="")
    case topic
    when ""
      return "chanserv plugin: interface the bot with the chanserv; topics: add, rm, list"
    when "add"
      return "chanserv add +status+ +channel+ [+nick+] => the bot will tell chanserv to set the status of +nick+ on +channel+ to +status+"
    when "rm"
      return "chanserv rm +status+ +channel+ [+nick+] => the bot will not tell chanserv to set the status of +nick+ on +channel+ to +status+ anymore"
    when "list"
      return "chanserv list => list current chanserv status modifiers"
    end
  end

  # Returns the chanserv name
  def cs_nick
    @bot.config['chanserv.name']
  end

  # say something to chanserv
  def cs_say(msg)
    @bot.say cs_nick, msg
  end

  def cs_add(m, params)
    status = params[:status].downcase
    ch = params[:channel].downcase
    who = params[:nick].downcase rescue ''
    as = @registry[:auto_status] || Array.new
    as << [status, ch, who]
    debug as.inspect
    @registry[:auto_status] = as
    m.okay
  end

  def cs_rm(m, params)
    status = params[:status].downcase
    ch = params[:channel].downcase
    who = params[:nick].downcase rescue ''
    as = @registry[:auto_status]
    unless as
      m.reply "No chanserv entries known!"
      return
    end
    as.delete [status, ch, who]
    debug as.inspect
    @registry[:auto_status] = as
    m.okay
  end

  def cs_list(m, params)
    unless @registry[:auto_status]
      m.reply "No chanserv entries known!"
      return
    end
    @registry[:auto_status].each { |status, ch, pre_who|
      who = pre_who.empty? ? "me (yes, me)" : pre_who
      m.reply "chanserv should #{status} #{who} on #{ch}"
    }

  end

  def join(m)
    return unless @registry[:auto_status]
    @registry[:auto_status].each { |status, ch, pre_who|
      who = pre_who.empty? ? @bot.nick : pre_who
      if m.channel.downcase == ch.downcase
        if who.downcase == m.source.downcase
          cs_say "#{status} #{ch} #{who}"
        end
      end
    }
  end

  def nick(m)
    return unless @registry[:auto_status]
    is_on = m.server.channels.inject(ChannelList.new) { |list, ch|
      list << ch if ch.users.include?(m.source)
      list
    }
    is_on.each { |channel|
      @registry[:auto_status].each { |status, ch, pre_who|
        who = pre_who.empty? ? @bot.nick : pre_who
        if channel.downcase == ch.downcase
          if who.downcase == m.source.downcase
            cs_say "#{status} #{ch} #{who}"
          end
        end
      }
    }
  end

  # This method gets delegated by the NickServ plugin after successfull identification
  def identified
    return unless @registry[:auto_status]
    @registry[:auto_status].each { |status, ch, who|
      if who.empty?
        cs_say "#{status} #{ch} #{@bot.nick}"
      end
    }
  end


end

plugin = ChanServPlugin.new
plugin.map 'chanserv add :status :channel [:nick]', :action => :cs_add
plugin.map 'chanserv rm :status :channel [:nick]', :action => :cs_rm
plugin.map 'chanserv list', :action => :cs_list

plugin.default_auth('*', false)

