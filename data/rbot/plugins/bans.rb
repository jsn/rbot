# Plugin for the Ruby IRC bot (http://linuxbrit.co.uk/rbot/)
#
# Managing kick and bans, automatically removing bans after timeouts, quiet bans, and kickban/quietban based on regexp
#
# Commands are little Ruby programs that run in the context of the command plugin. You
# can create them directly in an IRC channel, and invoke them just like normal rbot plugins.
#
# (c) 2006 Marco Gulino <marco@kmobiletools.org>
# Licensed under GPL V2.


class BansPlugin < Plugin
  def initialize
    super
     if @registry.has_key?(:bans)
       @bansregexps = @registry[:bans]
     else
       @bansregexps = Hash.new
     end

     if @registry.has_key?(:bansmasks)
	     @whitelist = @registry[:bansmasks]
     else
	     @whitelist = Hash.new
     end
    end


    def save
      @registry[:bans] = @bansregexps
      @registry[:bansmasks] = @whitelist
    end




  def help(plugin, topic="")
	  case topic
	  when "kickbans"
		return "bans ban|quietban nick [channel] [timer]: bans|quietbans a nick from the channel for a specified time. bans kick nick [channel] [message]: kicks <nick> from <channel> with kick <message>. bans kickban nick [channel] [timer] [message]: kick+ban, same parameters as before. timer is always specified as <number><unit>, like 3m, 10s, 1h."
	  when "whitelist"
		  return "bans addwhitelist <mask>: adds <mask> to whitelist (NEVER regexp ban this). bans whitelist: shows current whitelist. bans delwhitelist <key>: delete whitelist entry <key>."
	  when "regexpbans"
		  return "bans addregexp type [timer] regexp: listens for <regexp>, then do actions depending on <type> (\"quietban\" or \"kickban\", currently). If timer if specified, it removes the ban after timer expires. timer is always specified as <number><unit>, like 3m, 10s, 1h. bans delregexp <key>: remove watching for regexp <key>. bans listregexps: show current regexp watching list."
	  else
		  return "Topics: \"kickbans\", \"whitelist\", \"regexpbans\""
	  end
#    return "Channel administration plugin. bans ban nick [channel] [timer]: bans a nick from the channel for a specified time; bans unban nick [channel]: removes the ban on <nick>; bans quiet nick [channel] [timer] and bans unquiet nick [channel]: same as ban and unban, but uses quiet ban instead. Timer is specified as 6s, 10m, 2h. If channel is not specified will use current channel.\nbans listregexps|addregexp type timeout regexp|delregexp: regexp banning management. Type can be quietban or kickban"
  end


  def cmd_setmode(m, nick, channel, smode, time, umode )
    channel=channel != '####currentchannel' ? channel : m.target
    timercnt=/^(\d+)([smh])$/.match(time)[1]
    timeru=/^(\d+)([smh])$/.match(time)[2]
    timer = timercnt.to_i if timeru == "s"
    timer = timercnt.to_i*60 if timeru == "m"
    timer = timercnt.to_i*3600 if timeru == "h"
    if timer > 0 then @bot.timer.add_once(timer, m ) {|m|
      @bot.sendq("MODE #{channel} #{umode} #{nick}")
      #		m.reply("Undo mode")
    } end

    @bot.sendq("MODE #{channel} #{smode} #{nick}")
    #	m.reply "ban cmd nick=#{nick} channel=#{channel} timer=#{timercnt} #{timeru} #{timer}"
  end
  def cmd_dokick(m, nick, channel, message)
      channel=channel != '####currentchannel' ? channel : m.target
      @bot.sendq("KICK #{channel} #{nick} :#{message}")
  end


  def cmd_kick(m,params)
    cmd_dokick(m,params[:nick], params[:channel], params[:message])
  end
  def cmd_ban(m, params)
    cmd_setmode(m, params[:nick], params[:channel], "+b", params[:timer], "-b")
  end
  def cmd_kickban(m,params)
      cmd_setmode(m, params[:nick], params[:channel], "+b", params[:timer], "-b")
      cmd_dokick(m,params[:nick], params[:channel], params[:message])
  end


  def cmd_quietban(m, params)
    cmd_setmode(m, params[:nick], params[:channel], "+q", params[:timer], "-q")
  end
  def cmd_unban(m, params)
    cmd_setmode(m, params[:nick], params[:channel], "-b", "0s", "")
  end
  def cmd_unquiet(m, params)
    cmd_setmode(m, params[:nick], params[:channel], "-q", "0s", "")
  end

  def listen(m)
    if @bansregexps.length <= 0 then return end
    @whitelist.each_key do |key|
	    if Irc.netmaskmatch(@whitelist[key], m.source) then
		    return
	    end
	    next
    end

    @bansregexps.each_key do |key|
      match=@bansregexps[key][2]
      if m.message =~ /^.*#{match}.*$/i then
        case @bansregexps[key][0]
	when "quietban"
		cmd_setmode(m, m.sourcenick, m.channel, "+q", @bansregexps[key][1], "-q")
		return
	when "kickban"
                cmd_setmode(m, m.sourcenick, m.channel, "+b", @bansregexps[key][1], "-b")
		cmd_dokick(m, m.sourcenick, m.channel, "Autokick")
		return
	end
      end
      next
    end
  end

  def cmd_addregexp(m, params)
    toadd=Array[ params[:type], params[:timeout], "#{params[:regexp]}" ]
    regsize=@bansregexps.length+1
#    m.reply("Current registry size: #{regsize}")

    @bansregexps[regsize]=toadd
 
#    @bansregexps.store(toadd)
    regsize=@bansregexps.length
#    m.reply("New registry size: #{regsize}")
    m.reply("Done.")
  end
  def cmd_listregexp(m, params)
    if @bansregexps.length == 0
      m.reply("No regexps stored."); return
    end
    @bansregexps.each_key do |key|
	    m.reply("Key: #{key}, type: #{@bansregexps[key][0]}, timeout: #{@bansregexps[key][1]}, pattern: #{@bansregexps[key][2]}")
	    sleep 1
	    next
    end
  end
  def cmd_delregexp(m, params)
    index=params[:index]
    @bansregexps.each_key do |key|
	    if ( "#{key}" == "#{index}" ) then
		    @bansregexps.delete(key)
		    m.reply("Done.")
		    return
	    end
	    next
end
m.reply("Key #{index} not found.")
  end
  def cmd_whitelistadd(m, params)
    regsize=@whitelist.length+1
    @whitelist[regsize]=params[:netmask]
    m.reply("Done.")
  end
  def cmd_whitelist(m, params)
      if @whitelist.length == 0
	      m.reply("Whitelist is empty."); return
      end
      @whitelist.each_key do |key|
	      m.reply("Key: #{key}, netmask: #{@whitelist[key]}")
	      sleep 1
	      next
      end
  end
  def cmd_whitelistdel(m, params)
    index=params[:index]
    @whitelist.each_key do |key|
	    if ( "#{key}" == "#{index}" ) then
		    @whitelist.delete(key)
		    m.reply("Done.")
		    return
	    end
	    next
    end
    m.reply("Key #{index} not found.")
  end
end
plugin = BansPlugin.new
plugin.register("bans")

plugin.map 'bans whitelist', :action => 'cmd_whitelist', :auth => 'bans'
plugin.map 'bans delwhitelist :index', :action => 'cmd_whitelistdel', :auth => 'bans', :requirements => { :index => /^\d+$/ }
plugin.map 'bans addwhitelist :netmask', :action => 'cmd_whitelistadd', :auth => 'bans'
plugin.map 'bans delregexp :index', :action => 'cmd_delregexp', :auth => 'bans', :requirements => { :index => /^\d+$/ }
plugin.map 'bans addregexp :type :timeout *regexp', :action => 'cmd_addregexp', :auth => 'bans', :requirements => {:timeout => /^\d+[smh]$/, :type => /(quietban)|(kickban)/ }, :defaults => { :timeout => "0s" }
plugin.map 'bans listregexps', :action => 'cmd_listregexp', :auth => 'bans'
plugin.map 'bans ban :nick :channel :timer', :action => 'cmd_ban', :auth => 'bans', :requirements => {:timer => /^\d+[smh]$/, :channel => /^#+[^\s]+$/}, :defaults => {:channel => '####currentchannel', :timer => '0s'}
plugin.map 'bans quiet :nick :channel :timer', :action => 'cmd_quietban', :auth => 'bans', :requirements => {:timer => /^\d+[smh]$/, :channel => /^#+[^\s]+$/}, :defaults => {:channel => '####currentchannel', :timer => '0s'}

plugin.map 'bans kick :nick :channel *message', :action => 'cmd_kick', :auth => 'bans', :requirements => {:channel => /^#+[^\s]+$/}, :defaults => {:channel => '####currentchannel', :message => 'Au revoir.'}
plugin.map 'bans kickban :nick :channel :timer *message', :action => 'cmd_kickban', :auth => 'bans', :requirements => {:channel => /^#+[^\s]+$/, :timer => /^\d+[smh]$/ }, :defaults => {:channel => '####currentchannel', :message => 'Au revoir.', :timer => '0s'}


plugin.map 'bans unban :nick :channel', :action => 'cmd_unban', :auth => 'bans', :requirements => { :channel => /^#+[^\s]+$/}, :defaults => {:channel =>	'####currentchannel'}
plugin.map 'bans unquiet :nick :channel', :action => 'cmd_unquiet', :auth => 'bans', :requirements => { :channel => /^#+[^\s]+$/}, :defaults => {:channel =>	'####currentchannel'}

#plugin.map 'admin kick :nick :channel *message', :action => 'cmd_kick', :auth => 'admin'
#plugin.map 'admin kickban :nick :channel *message', :action => 'cmd_kickban' :auth => 'admin'
#plugin.register("quietban")
#plugin.register("kickban")
