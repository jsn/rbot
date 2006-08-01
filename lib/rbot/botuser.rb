#-- vim:sw=2:et
#++
# :title: User management
#
# rbot user management
# Author:: Giuseppe Bilotta (giuseppe.bilotta@gmail.com)
# Copyright:: Copyright (c) 2006 Giuseppe Bilotta
# License:: GPLv2

#--
#####
####
### Discussion on IRC on how to implement it
##
#
# <tango_>	a. do we want user groups together with users?
# <markey>	hmm
# <markey>	let me think about it
# <markey>	generally I would say: as simple as possible while keeping it as flexible as need be
# <tango_>	I think we can put user groups in place afterwards if we build the structure right
# <markey>	prolly, yes
# <tango_>	so
# <tango_>	each plugin registers a name
# <tango_>	so rather than auth level we have +name -name
# <markey>	yes
# <markey>	much better
# <tango_>	the default is +name for every plugin, except when the plugin tells otherwise
# <markey>	although.. 
# <markey>	if I only want to allow you access to one plugin
# <markey>	I have lots of typing to do
# <tango_>	nope
# <tango_>	we allow things like -*
# <markey>	ok
# <tango_>	and + has precedence
# <tango_>	hm no, not good either
# <tango_>	because we want bot -* +onething and +* -onething to work
# <markey>	but then: one plugin currently can have several levels, no?
# <tango_>	of course
# <markey>	commandedit, commanddel, commandfoo
# <tango_>	name.command ?
# <markey>	yep
# <tango_>	(then you can't have dots in commands
# <tango_>	maybe name:command
# <markey>	or name::comand
# <markey>	like a namespace
# <tango_>	ehehehe yeah I like it :)
# <tango_>	tel
# <tango_>	brb
# <markey>	usermod setcaps eean -*
# <markey>	usermod setcaps eean +quiz::edit
# <markey>	great
# <markey>	or even
# <markey>	auth eean -*, +quiz::edit
# <markey>	awesome
# <markey>	auth eean -*, +quiz::edit, +command, -command::del
# <tango_>	yes
# <markey>	you know, the default should be -*
# <markey>	because
# <markey>	in the time between adding the user and changing auth
# <markey>	it's insecure
# <markey>	user could do havoc
# <markey>	useradd eean, then eean does "~quit", before I change auth
# <tango_>	nope
# <markey>	perhaps we should allow combining useradd with auth
# <tango_>	the default should be +* -important stuff
# <markey>	ok
# <tango_>	how to specify channel stuff?
# <markey>	for one, when you issue the command on the channel itself
# <markey>	then it's channel relative
# <markey>	perhaps
# <markey>	or
# <tango_>	yes but I was thinking more about the syntax
# <markey>	auth eean #rbot -quiz
# <tango_>	hm
# <markey>	or maybe: treat channels like users: auth #rbot -quiz
# <markey>	would shut up quiz in #rbot
# <markey>	hm
# <markey>	heh
# <tango_>	auth * #rbot -quiz
# <markey>	not sure I'm making sense here ;)
# <tango_>	I think syntax should be auth [usermask] [channelmask] [modes]
# <markey>	yes
# <markey>	modes separated by comma?
# <tango_>	where channelmask is implied to be *
# <tango_>	no we can have it spacesplit
# <markey>	great
# <markey>	ok
# <tango_>	modes are detected by +-
# <tango_>	so you can do something like auth markey #rbot -quiz #amarok -chuck
# <markey>	also I like "auth" a lot more than "usermod foo"
# <markey>	yep
# <tango_>	I don't understand why the 'mod'
# <tango_>	we could have all auth commands start with use
# <tango_>	user
# <tango_>	user add
# <tango_>	user list
# <tango_>	user del
# <markey>	yes
# <tango_>	user auth
# <tango_>	hm
# <tango_>	and maybe auth as a synonym for user auth
# <markey>	this is also uncomfortable: usermod wants the full user mask
# <markey>	you have to copy/paste it
# <tango_>	no
# <tango_>	can't you use *?
# <markey>	sorry not sure
# <markey>	but this shows, it's not inuitive
# <markey>	I've read the docs
# <markey>	but didn't know how to use it really
# <tango_>	markey!*@*
# <markey>	that's not very intuitive
# <tango_>	we could use nick as a synonym for nick!*@* if it's too much for you :D
# <markey>	usermod markey foo should suffice
# <markey>	rememember: you're a hacker. when rbot gets many new users, they will often be noobs
# <markey>	gotta make things simple to use
# <tango_>	but the hostmask is only needed for the user creation
# <markey>	really? then forget what I said, sorry
# <tango_>	I think so
# <tango_>	,help auth
# <testbot>	Auth module (User authentication) topics: setlevel, useradd, userdel, usermod, auth, levels, users, whoami, identify
# <tango_>	,help usermod
# <testbot>	no help for topic usermod
# <tango_>	,help auth usermod
# <testbot>	usermod <username> <item> <value> => Modify <username>s settings. Valid <item>s are: hostmask, (+|-)hostmask, password, level (private addressing only)
# <tango_>	see? it's username, not nick :D
# <markey>	btw, help usermod should also work
# <tango_>	,help auth useradd
# <testbot>	useradd <username> => Add user <mask>, you still need to set him up correctly (private addressing only)
# <markey>	instead of help auth usermode
# <markey>	when it's not ambiguous
# <tango_>	and the help for useradd is wrong
# <markey>	for the website, we could make a logo contest :) the current logo looks like giblet made it in 5 minutes ;)
# <markey>	ah well, for 1.0 maybe
# <tango_>	so a user on rbot is given by
# <tango_>	username, password, hostmasks, permissions
# <markey>	yup
# <tango_>	the default permission is +* -importantstuff
# <markey>	how defines importantstuff?
# <markey>	you mean like core and auth?
# <tango_>	yes
# <markey>	ok
# <tango_>	but we can decide about this :)
# <markey>	some plugins are dangerous by default
# <markey>	like command plugin
# <markey>	you can do all sorts of nasty shit with it
# <tango_>	then command plugin will do something like: command.defaultperm("-command")
# <markey>	yes, good point
# <tango_>	this is then added to the default permissions (user * channel *)
# <tango_>	when checking for auth, we go like this:
# <tango_>	hm
# <tango_>	check user * channel *
# <tango_>	then user name channel *
# <tango_>	then user * channel name
# <tango_>	then user name channel name
# <tango_>	for each of these combinations we match against * first, then against command, and then against command::subcommand
# <markey>	yup
# <tango_>	setting or resetting it depending on wether it's + or -
# <tango_>	the final result gives us the permission
# <tango_>	implementation detail
# <tango_>	username and passwords are strings
# <markey>	(I might rename the command plugin, the name is somewhat confusing)
# <tango_>	yeah
# <tango_>	hostmasks are hostmasks
# <markey>	also I'm pondering to restrict it more: disallow access to @bot
# <tango_>	permissions are in the form [ [channel, {command => bool, ...}] ...]
#++

require 'singleton'

module Irc

  # This method raises a TypeError if _user_ is not of class User
  #
  def error_if_not_user(user)
    raise TypeError, "#{user.inspect} must be of type Irc::User and not #{user.class}" unless user.class <= User
  end

  # This method raises a TypeError if _chan_ is not of class Chan
  #
  def error_if_not_channel(chan)
    raise TypeError, "#{chan.inspect} must be of type Irc::User and not #{chan.class}" unless chan.class <= Channel
  end


  # This module contains the actual Authentication stuff
  #
  module Auth

    # Generate a random password of length _l_
    #
    def random_password(l=8)
      pwd = ""
      8.times do
        pwd += (rand(26) + (rand(2) == 0 ? 65 : 97) ).chr
      end
      return pwd
    end


    # An Irc::Auth::Command defines a command by its "path":
    #
    #   base::command::subcommand::subsubcommand::subsubsubcommand
    #
    class Command

      attr_reader :command, :path

      # A method that checks if a given _cmd_ is in a form that can be
      # reduced into a canonical command path, and if so, returns it
      #
      def sanitize_command_path(cmd)
        pre = cmd.to_s.downcase.gsub(/^\*?(?:::)?/,"").gsub(/::$/,"")
        return pre if pre.empty?
        return pre if pre =~ /^\S+(::\S+)*$/
        raise TypeError, "#{cmd.inspect} is not a valid command"
      end

      # Creates a new Command from a given string; you can then access
      # the command as a symbol with the :command method and the whole
      # path as :path
      #
      #   Command.new("core::auth::save").path => [:"", :core, :"core::auth", :"core::auth::save"]
      #
      #   Command.new("core::auth::save").command => :"core::auth::save"
      #
      def initialize(cmd)
        cmdpath = sanitize_command_path(cmd).split('::')
        seq = cmdpath.inject([""]) { |list, cmd|
          list << (list.last ? list.last + "::" : "") + cmd
        }
        @path = seq.map { |k|
          k.to_sym
        }
        @command = path.last
      end
    end

    # This method raises a TypeError if _user_ is not of class User
    #
    def error_if_not_command(cmd)
      raise TypeError, "#{cmd.inspect} must be of type Irc::Auth::Command and not #{cmd.class}" unless cmd.class <= Command
    end


    # This class describes a permission set
    class PermissionSet

      # Create a new (empty) PermissionSet
      #
      def initialize
        @perm = {}
      end

      # Sets the permission for command _cmd_ to _val_,
      # creating intermediate permissions if needed.
      #
      def set_permission(cmd, val)
        raise TypeError, "#{val.inspect} must be true or false" unless [true,false].include?(val)
        error_if_not_command(cmd)
        cmd.path.each { |k|
          set_permission(k.to_s, true) unless @perm.has_key?(k)
        }
        @perm[path.last] = val
      end

      # Tells if command _cmd_ is permitted. We do this by returning
      # the value of the deepest Command#path that matches.
      #
      def allow?(cmd)
        error_if_not_command(cmd)
        allow = nil
        cmd.path.reverse.each { |k|
          if @perm.has_key?(k)
            allow = @perm[k]
            break
          end
        }
        return allow
      end
    end


    # This is the basic class for bot users: they have a username, a password, a
    # list of netmasks to match against, and a list of permissions.
    #
    class BotUser

      attr_reader :username
      attr_reader :password
      attr_reader :netmasks

      # Create a new BotUser with given username
      def initialize(username)
        @username = BotUser.sanitize_username(username)
        @password = nil
        @netmasks = NetmaskList.new
        @perm = {}
      end

      # Resets the password by creating a new onw
      def reset_password
        @password = random_password
      end

      # Sets the permission for command _cmd_ to _val_ on channel _chan_
      #
      def set_permission(cmd, val, chan="*")
        k = chan.to_s.to_sym
        @perm[k] = PermissionSet.new unless @perm.has_key?(k)
        @perm[k].set_permission(cmd, val)
      end

      # Checks if BotUser is allowed to do something on channel _chan_,
      # or on all channels if _chan_ is nil
      #
      def allow?(cmd, chan=nil)
        if chan
          k = chan.to_s.to_sym
        else
          k = :*
        end
        allow = nil
        if @perm.has_key?(k)
          allow = @perm[k].allow?(cmd)
        end
        return allow
      end

      # Adds a Netmask
      #
      def add_netmask(mask)
        case mask
        when Netmask
          @netmasks << mask
        else
          @netmasks << Netmask(mask)
        end
      end

      # Removes a Netmask
      #
      def delete_netmask(mask)
        case mask
        when Netmask
          m = mask
        else
          m << Netmask(mask)
        end
        @netmasks.delete(m)
      end

      # Removes all <code>Netmask</code>s
      def reset_netmask_list
        @netmasks = NetmaskList.new
      end

      # This method checks if BotUser has a Netmask that matches _user_
      def knows?(user)
        error_if_not_user(user)
        known = false
        @netmasks.each { |n|
          if user.matches?(n)
            known = true
            break
          end
        }
        return known
      end

      # This method gets called when User _user_ wants to log in.
      # It returns true or false depending on whether the password
      # is right. If it is, the Netmask of the user is added to the
      # list of acceptable Netmask unless it's already matched.
      def login(user, password)
        if password == @password
          add_netmask(user) unless knows?(user)
          return true
        else
          return false
        end
      end

      # # This method gets called when User _user_ has logged out as this BotUser
      # def logout(user)
      #   delete_netmask(user) if knows?(user)
      # end

      # This method sanitizes a username by chomping, downcasing
      # and replacing any nonalphanumeric character with _
      #
      def BotUser.sanitize_username(name)
        return name.to_s.chomp.downcase.gsub(/[^a-z0-9]/,"_")
      end

      # This method sets the password if the proposed new password
      # is valid
      def password=(pwd=nil)
        if pwd
          begin
            raise InvalidPassword, "#{pwd} contains invalid characters" if pwd !~ /^[A-Za-z0-9]+$/
            raise InvalidPassword, "#{pwd} too short" if pwd.length < 4
            @password = pwd
          rescue InvalidPassword => e
            raise e
          rescue => e
            raise InvalidPassword, "Exception #{e.inspect} while checking #{pwd}"
          end
        else
          reset_password
        end
      end
    end


    # This is the anonymous BotUser: it's used for all users which haven't
    # identified with the bot
    #
    class AnonBotUserClass < BotUser
      include Singleton
      def initialize
        super("anonymous")
      end
      private :login, :add_netmask, :delete_netmask

      # Anon knows everybody
      def knows?(user)
        error_if_not_user(user)
        return true
      end

      # Resets the NetmaskList
      def reset_netmask_list
        super
        add_netmask("*!*@*")
      end
    end

    # Returns the only instance of AnonBotUserClass
    #
    def Auth::anonbotuser
      return AnonBotUserClass.instance
    end

    # This is the BotOwner: he can do everything
    #
    class BotOwnerClass < BotUser
      include Singleton
      def initialize
        super("owner")
      end

      def allow?(cmd, chan=nil)
        return true
      end
    end

    # Returns the only instance of BotOwnerClass
    #
    def Auth::botowner
      return BotOwnerClass.instance
    end


    # This is the AuthManagerClass singleton, used to manage User/BotUser connections and
    # everything
    #
    class AuthManagerClass
      include Singleton

      # The instance manages two <code>Hash</code>es: one that maps
      # <code>Irc::User</code>s onto <code>BotUser</code>s, and the other that maps
      # usernames onto <code>BotUser</code>
      def initialize
        bot_associate(nil)
      end

      def bot_associate(bot)
        raise "Cannot associate with a new bot! Save first" if defined?(@has_changes) && @has_changes

        reset_hashes

        # Associated bot
        @bot = bot

        # This variable is set to true when there have been changes
        # to the botusers list, so that we know when to save
        @has_changes = false
      end

      # resets the hashes
      def reset_hashes
        @botusers = Hash.new
        @allbotusers = Hash.new
        [Auth::anonbotuser, Auth::botowner].each { |x| @allbotusers[x.username.to_sym] = x }
      end

      # load botlist from userfile
      def load_merge(filename=nil)
        # TODO
        raise NotImplementedError
        @has_changes = true
      end

      def load(filename=nil)
        reset_hashes
        load_merge(filename)
      end

      # save botlist to userfile
      def save(filename=nil)
        return unless @has_changes
        # TODO
        raise NotImplementedError
      end

      # checks if we know about a certain BotUser username
      def include?(botusername)
        @allbotusers.has_key?(botusername.to_sym)
      end

      # Maps <code>Irc::User</code> to BotUser
      def irc_to_botuser(ircuser)
        error_if_not_user(ircuser)
        return @botusers[ircuser] || anonbotuser
      end

      # creates a new BotUser
      def create_botuser(name, password=nil)
        n = BotUser.sanitize_username(name)
        k = n.to_sym
        raise "BotUser #{n} exists" if include?(k)
        bu = BotUser.new(n)
        bu.password = password
        @allbotusers[k] = bu
      end

      # Logs Irc::User _ircuser_ in to BotUser _botusername_ with password _pwd_
      #
      # raises an error if _botusername_ is not a known BotUser username
      #
      # It is possible to autologin by Netmask, on request
      #
      def login(ircuser, botusername, pwd, bymask = false)
        error_if_not_user(ircuser)
        n = BotUser.sanitize_username(name)
        k = n.to_sym
        raise "No such BotUser #{n}" unless include?(k)
        if @botusers.has_key?(ircuser)
          # TODO
          # @botusers[ircuser].logout(ircuser)
        end
        bu = @allbotusers[k]
        if bymask && bu.knows?(user)
          @botusers[ircuser] = bu
          return true
        elsif bu.login(ircuser, pwd)
          @botusers[ircuser] = bu
          return true
        end
        return false
      end

      # Checks if User _user_ can do _cmd_ on _chan_.
      #
      # Permission are checked in this order, until a true or false
      # is returned:
      # * associated BotUser on _chan_
      # * associated BotUser on all channels
      # * anonbotuser on _chan_
      # * anonbotuser on all channels
      #
      def allow?(user, cmdtxt, chan=nil)
        error_if_not_user(user)
        cmd = Command.new(cmdtxt)
        allow = nil
        botuser = @botusers[user]
        case chan
        when User
          chan = "?"
        when Channel
          chan = chan.name
        end

        allow = botuser.allow?(cmd, chan) if chan
        return allow unless allow.nil?
        allow = botuser.allow?(cmd)
        return allow unless allow.nil?

        unless botuser == anonbotuser
          allow = anonbotuser.allow?(cmd, chan) if chan
          return allow unless allow.nil?
          allow = anonbotuser.allow?(cmd)
          return allow unless allow.nil?
        end

        raise "Could not check permission for user #{user.inspect} to run #{cmdtxt.inspect} on #{chan.inspect}"
      end
    end

    # Returns the only instance of AuthManagerClass
    #
    def Auth.authmanager
      return AuthManagerClass.instance
    end
  end
end
