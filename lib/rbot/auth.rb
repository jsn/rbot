module Irc

  # globmask:: glob to test with
  # netmask::  netmask to test against
  # Compare a netmask with a standard IRC glob, e.g foo!bar@baz.com would
  # match *!*@baz.com, foo!*@*, *!bar@*, etc.
  def Irc.netmaskmatch( globmask, netmask )
    regmask = Regexp.escape( globmask )
    regmask.gsub!( /\\\*/, '.*' )
    return true if(netmask =~ /#{regmask}/i)
    return false
  end

  # check if a string is an actual IRC hostmask
  def Irc.ismask?(mask)
    mask =~ /^.+!.+@.+$/
  end

  Struct.new( 'UserData', :level, :password, :hostmasks )

  # User-level authentication to allow/disallow access to bot commands based
  # on hostmask and userlevel.
  class IrcAuth
    BotConfig.register BotConfigStringValue.new( 'auth.password',
      :default => 'rbotauth', :wizard => true,
      :desc => 'Your password for maxing your auth with the bot (used to associate new hostmasks with your owner-status etc)' )
    BotConfig.register BotConfigIntegerValue.new( 'auth.default_level',
      :default => 10, :wizard => true,
      :desc => 'The default level for new/unknown users' )

    # create a new IrcAuth instance.
    # bot:: associated bot class
    def initialize(bot)
      @bot = bot
      @users = Hash.new do
        Struct::UserData.new(@bot.config['auth.default_level'], '', [])
      end
      @levels = Hash.new(0)
      @currentUsers = Hash.new( nil )
      if( File.exist?( "#{@bot.botclass}/users.yaml" ) )
        File.open( "#{@bot.botclass}/users.yaml" ) { |file|
          # work around YAML not maintaining the default proc
          @loadedusers = YAML::parse(file).transform
          @users.update(@loadedusers)
        }
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
      if @levels.length < 1
        raise RuntimeError, "No valid levels.rbot found! If you really want a free-for-all bot and this isn't the result of a previous error, write a proper levels.rbot"
      end
    end

    # save current users and levels to files.
    # levels are written to #{botclass}/levels.rbot
    # users are written to #{botclass}/users.yaml
    def save
      Dir.mkdir("#{@bot.botclass}") if(!File.exist?("#{@bot.botclass}"))
      begin
        debug "Writing new users.yaml ..."
        File.open("#{@bot.botclass}/users.yaml.new", 'w') do |file|
          file.puts @users.to_yaml
        end
        debug "Officializing users.yaml ..."
        File.rename("#{@bot.botclass}/users.yaml.new",
                    "#{@bot.botclass}/users.yaml")
      rescue
        error "failed to write configuration file users.yaml! #{$!}"
        error "#{e.class}: #{e}"
        error e.backtrace.join("\n")
      end
      begin
        debug "Writing new levels.rbot ..."
        File.open("#{@bot.botclass}/levels.rbot.new", 'w') do |file|
          @levels.each do |key, value|
            file.puts "#{value} #{key}"
          end
        end
        debug "Officializing levels.rbot ..."
        File.rename("#{@bot.botclass}/levels.rbot.new",
                    "#{@bot.botclass}/levels.rbot")
      rescue
        error "failed to write configuration file levels.rbot! #{$!}"
        error "#{e.class}: #{e}"
        error e.backtrace.join("\n")
      end
    end

    # command:: command user wishes to perform
    # mask::    hostmask of user
    # tell::    optional recipient for "insufficient auth" message
    #
    # returns true if user with hostmask +mask+ is permitted to perform
    # +command+ optionally pass tell as the target for the "insufficient auth"
    # message, if the user is not authorised
    def allow?( command, mask, tell=nil )
      auth = @users[matchingUser(mask)].level # Directly using @users[] is possible, because UserData has a default setting
        if( auth >= @levels[command] )
          return true
        else
          debug "#{mask} is not allowed to perform #{command}"
          @bot.say tell, "insufficient \"#{command}\" auth (have #{auth}, need #{@levels[command]})" if tell
          return false
        end
    end

    # add user with hostmask matching +mask+ with initial auth level +level+
    def useradd( username, level=@bot.config['auth.default_level'], password='', hostmask='*!*@*' )
      @users[username] = Struct::UserData.new( level, password, [hostmask] ) if ! @users.has_key? username
    end

    # mask:: mask of user to remove
    # remove user with mask +mask+
    def userdel( username )
      @users.delete( username ) if @users.has_key? username
    end

    def usermod( username, item, value=nil )
      if @users.has_key?( username )
        case item
          when 'hostmask'
            if Irc.ismask?( value )
              @users[username].hostmasks = [ value ]
              return true
            end
          when '+hostmask'
            if Irc.ismask?( value )
              @users[username].hostmasks += [ value ]
              return true
            end
          when '-hostmask'
            if Irc.ismask?( value )
              @users[username].hostmasks -= [ value ]
              return true
            end
          when 'password'
              @users[username].password = value
              return true
          when 'level'
              @users[username].level = value.to_i
              return true
          else
            debug "usermod: Tried to modify unknown item #{item}"
	    # @bot.say tell, "Unknown item #{item}" if tell
        end
      end
      return false
    end

    # command:: command to adjust
    # level::   new auth level for the command
    # set required auth level of +command+ to +level+
    def setlevel(command, level)
      @levels[command] = level
    end

    def matchingUser( mask )
      currentUser = nil
      currentLevel = 0
      @users.each { |user, data| # TODO Will get easier if YPaths are used...
        if data.level > currentLevel
          data.hostmasks.each { |hostmask|
            if Irc.netmaskmatch( hostmask, mask )
              currentUser = user
              currentLevel = data.level
            end
          }
        end
      }
      currentUser
    end

    def identify( mask, username, password )
      return false unless @users.has_key?(username) && @users[username].password == password
      @bot.auth.usermod( username, '+hostmask', mask )
      return true
    end

    # return all currently defined commands (for which auth is required) and
    # their required authlevels
    def showlevels
      reply = 'Current levels are:'
      @levels.sort.each { |key, value|
        reply += " #{key}(#{value})"
      }
      reply
    end

    # return all currently defined users and their authlevels
    def showusers
      reply = 'Current users are:'
      @users.sort.each { |key, value|
        reply += " #{key}(#{value.level})"
      }
      reply
    end

    def showdetails( username )
      if @users.has_key? username
        reply = "#{username}(#{@users[username].level}):"
        @users[username].hostmasks.each { |hostmask|
          reply += " #{hostmask}"
        }
      end
      reply
    end

    # module help
    def help(topic='')
      case topic
        when 'setlevel'
          return 'setlevel <command> <level> => Sets required level for <command> to <level> (private addressing only)'
        when 'useradd'
          return 'useradd <username> => Add user <mask>, you still need to set him up correctly (private addressing only)'
        when 'userdel'
          return 'userdel <username> => Remove user <username> (private addressing only)'
        when 'usermod'
          return 'usermod <username> <item> <value> => Modify <username>s settings. Valid <item>s are: hostmask, (+|-)hostmask, password, level (private addressing only)'
        when 'auth'
          return 'auth <masterpw> => Create a user with your hostmask and master password as bot master (private addressing only)'
        when 'levels'
          return 'levels => list commands and their required levels (private addressing only)'
        when 'users'
          return 'users [<username>]=> list users and their levels or details about <username> (private addressing only)'
        when 'whoami'
          return 'whoami => Show as whom you are recognized (private addressing only)'
        when 'identify'
          return 'identify <username> <password> => Identify your hostmask as belonging to <username> (private addressing only)'
        else
          return 'Auth module (User authentication) topics: setlevel, useradd, userdel, usermod, auth, levels, users, whoami, identify'
      end
    end

    # privmsg handler
    def privmsg(m)
     if(m.address? && m.private?)
      case m.message
        when (/^setlevel\s+(\S+)\s+(\d+)$/)
          if( @bot.auth.allow?( 'auth', m.source, m.replyto ) )
            @bot.auth.setlevel( $1, $2.to_i )
            m.reply "level for #$1 set to #$2"
          end
        when( /^useradd\s+(\S+)/ ) # FIXME Needs review!!! (\s+(\S+)(\s+(\S+)(\s+(\S+))?)?)? Should this part be added to make complete useradds possible?
          if( @bot.auth.allow?( 'auth', m.source, m.replyto ) )
            @bot.auth.useradd( $1 )
            m.reply "added user #$1, please set him up correctly"
          end
        when( /^userdel\s+(\S+)/ )
          if( @bot.auth.allow?( 'auth', m.source, m.replyto ) )
            @bot.auth.userdel( $1 )
            m.reply "user #$1 is gone"
          end
        when( /^usermod\s+(\S+)\s+(\S+)\s+(\S+)/ )
          if( @bot.auth.allow?('auth', m.source, m.replyto ) )
            if( @bot.auth.usermod( $1, $2, $3 ) )
              m.reply "Set #$2 of #$1 to #$3"
            else
              m.reply "Failed to set #$2 of #$1 to #$3"
            end
          end
        when( /^setpassword\s+(\S+)/ )
	  password = $1
          user = @bot.auth.matchingUser( m.source )
          if user
	    if @bot.auth.usermod(user, 'password', password)
	      m.reply "Your password has been set to #{password}"
	    else
	      m.reply "Couldn't set password"
	    end
          else
            m.reply 'You don\'t belong to any user.'
          end
        when (/^auth\s+(\S+)/)
          if( $1 == @bot.config['auth.password'] )
            if ! @users.has_key? 'master'
              @bot.auth.useradd( 'master', 1000, @bot.config['auth.password'], m.source )
            else
              @bot.auth.usermod( 'master', '+hostmask', m.source )
            end
            m.reply 'Identified, security level maxed out'
          else
            m.reply 'Incorrect password'
          end
        when( /^identify\s+(\S+)\s+(\S+)/ )
          if @bot.auth.identify( m.source, $1, $2 )
            m.reply "Identified as #$1 (#{@users[$1].level})"
          else
            m.reply 'Incorrect username/password'
          end
        when( 'whoami' )
          user = @bot.auth.matchingUser( m.source )
          if user
            m.reply "I recognize you as #{user} (#{@users[user].level})"
          else
            m.reply 'You don\'t belong to any user.'
          end
        when( /^users\s+(\S+)/ )
          m.reply @bot.auth.showdetails( $1 ) if( @bot.auth.allow?( 'auth', m.source, m.replyto ) )
        when ( 'levels' )
          m.reply @bot.auth.showlevels if( @bot.auth.allow?( 'config', m.source, m.replyto ) )
        when ( 'users' )
          m.reply @bot.auth.showusers if( @bot.auth.allow?( 'users', m.source, m.replyto ) )
      end
     end
    end
  end
end
