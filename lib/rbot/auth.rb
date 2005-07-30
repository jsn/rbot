module Irc

  # globmask:: glob to test with
  # netmask::  netmask to test against
  # Compare a netmask with a standard IRC glob, e.g foo!bar@baz.com would
  # match *!*@baz.com, foo!*@*, *!bar@*, etc.
  def Irc.netmaskmatch(globmask, netmask)
    regmask = globmask.gsub(/\*/, ".*?")
    return true if(netmask =~ /#{regmask}/)
    return false
  end

  # check if a string is an actual IRC hostmask
  def Irc.ismask(mask)
    mask =~ /^.+!.+@.+$/
  end

  
  # User-level authentication to allow/disallow access to bot commands based
  # on hostmask and userlevel.
  class IrcAuth
    BotConfig.register('auth.password', :type => BotConfig::Password, :default => "Your password for maxing your auth with the bot (used to associate new hostmasks with your owner-status etc)")
    
    # create a new IrcAuth instance.
    # bot:: associated bot class
    def initialize(bot)
      @bot = bot
      @users = Hash.new(0)
      @levels = Hash.new(0)
      if(File.exist?("#{@bot.botclass}/users.rbot"))
        IO.foreach("#{@bot.botclass}/users.rbot") do |line|
          if(line =~ /\s*(\d+)\s*(\S+)/)
            level = $1.to_i
            mask = $2
            @users[mask] = level
          end
        end
      end
      if(File.exist?("#{@bot.botclass}/levels.rbot"))
        IO.foreach("#{@bot.botclass}/levels.rbot") do |line|
          if(line =~ /\s*(\d+)\s*(\S+)/)
            level = $1.to_i
            command = $2
            @levels[command] = level
          end
        end
      end
    end

    # save current users and levels to files.
    # levels are written to #{botclass}/levels.rbot
    # users are written to #{botclass}/users.rbot
    def save
      Dir.mkdir("#{@bot.botclass}") if(!File.exist?("#{@bot.botclass}"))
      File.open("#{@bot.botclass}/users.rbot", "w") do |file|
        @users.each do |key, value|
          file.puts "#{value} #{key}"
        end
      end
      File.open("#{@bot.botclass}/levels.rbot", "w") do |file|
        @levels.each do |key, value|
          file.puts "#{value} #{key}"
        end
      end
    end

    # command:: command user wishes to perform
    # mask::    hostmask of user
    # tell::    optional recipient for "insufficient auth" message
    #
    # returns true if user with hostmask +mask+ is permitted to perform
    # +command+ optionally pass tell as the target for the "insufficient auth"
    # message, if the user is not authorised
    def allow?(command, mask, tell=nil)
      auth = userlevel(mask)
      if(auth >= @levels[command])
        return true
      else
        debug "#{mask} is not allowed to perform #{command}"
        @bot.say tell, "insufficient \"#{command}\" auth (have #{auth}, need #{@levels[command]})" if tell
        return false
      end
    end

    # add user with hostmask matching +mask+ with initial auth level +level+
    def useradd(mask, level)
      if(Irc.ismask(mask))
        @users[mask] = level
      end
    end
    
    # mask:: mask of user to remove
    # remove user with mask +mask+
    def userdel(mask)
      if(Irc.ismask(mask))
        @users.delete(mask)
      end
    end

    # command:: command to adjust
    # level::   new auth level for the command
    # set required auth level of +command+ to +level+
    def setlevel(command, level)
      @levels[command] = level
    end

    # specific users.
    # mask:: mask of user
    # returns the authlevel of user with mask +mask+
    # finds the matching user which has the highest authlevel (so you can have
    # a default level of 5 for *!*@*, and yet still give higher levels to
    def userlevel(mask)
      # go through hostmask list, find match with _highest_ level (all users
      # will match *!*@*)
      level = 0
      @users.each {|user,userlevel|
        if(Irc.netmaskmatch(user, mask))
          level = userlevel if userlevel > level
        end
      }
      level
    end

    # return all currently defined commands (for which auth is required) and
    # their required authlevels
    def showlevels
      reply = "Current levels are:"
      @levels.sort.each {|a|
        key = a[0]
        value = a[1]
        reply += " #{key}(#{value})"
      }
      reply
    end

    # return all currently defined users and their authlevels
    def showusers
      reply = "Current users are:"
      @users.sort.each {|a|
        key = a[0]
        value = a[1]
        reply += " #{key}(#{value})"
      }
      reply
    end
    
    # module help
    def help(topic="")
      case topic
        when "setlevel"
          return "setlevel <command> <level> => Sets required level for <command> to <level> (private addressing only)"
        when "useradd"
          return "useradd <mask> <level> => Add user <mask> at level <level> (private addressing only)"
        when "userdel"
          return "userdel <mask> => Remove user <mask> (private addressing only)"
        when "auth"
          return "auth <masterpw> => Recognise your hostmask as bot master (private addressing only)"
        when "levels"
          return "levels => list commands and their required levels (private addressing only)"
        when "users"
          return "users => list users and their levels (private addressing only)"
        else
          return "Auth module (User authentication) topics: setlevel, useradd, userdel, auth, levels, users"
      end
    end

    # privmsg handler
    def privmsg(m)
     if(m.address? && m.private?)
      case m.message
        when (/^setlevel\s+(\S+)\s+(\d+)$/)
          if(@bot.auth.allow?("auth", m.source, m.replyto))
            @bot.auth.setlevel($1, $2.to_i)
            m.reply "level for #$1 set to #$2"
          end
        when (/^useradd\s+(\S+)\s+(\d+)/)
          if(@bot.auth.allow?("auth", m.source, m.replyto))
            @bot.auth.useradd($1, $2.to_i)
            m.reply "added user #$1 at level #$2"
          end
        when (/^userdel\s+(\S+)/)
          if(@bot.auth.allow?("auth", m.source, m.replyto))
            @bot.auth.userdel($1)
            m.reply "user #$1 is gone"
          end
        when (/^auth\s+(\S+)/)
          if($1 == @bot.config["auth.password"])
            @bot.auth.useradd(Regexp.escape(m.source), 1000)
            m.reply "Identified, security level maxed out"
          else
            m.reply "incorrect password"
          end
        when ("levels")
          m.reply @bot.auth.showlevels if(@bot.auth.allow?("config", m.source, m.replyto))
        when ("users")
          m.reply @bot.auth.showusers if(@bot.auth.allow?("config", m.source, m.replyto))
      end
     end
    end
  end
end
