#-- vim:sw=2:et
#++
# :title: User management
#
# rbot user management
# Author:: Giuseppe Bilotta (giuseppe.bilotta@gmail.com)
# Copyright:: Copyright (c) 2006 Giuseppe Bilotta
# License:: GPLv2

require 'singleton'


module Irc


  # This module contains the actual Authentication stuff
  #
  module Auth

    BotConfig.register BotConfigStringValue.new( 'auth.password',
      :default => 'rbotauth', :wizard => true,
      :desc => 'Password for the bot owner' )
    BotConfig.register BotConfigBooleanValue.new( 'auth.login_by_mask',
      :default => 'false',
      :desc => 'Set true if new botusers should allow logging in without a password when the user netmask is known')
    BotConfig.register BotConfigBooleanValue.new( 'auth.autologin',
      :default => 'false',
      :desc => 'Set true if new botusers should try to recognize IRC users without a need to manually login')
    # BotConfig.register BotConfigIntegerValue.new( 'auth.default_level',
    #   :default => 10, :wizard => true,
    #   :desc => 'The default level for new/unknown users' )

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
      #   Command.new("core::auth::save").path => [:"*", :"core", :"core::auth", :"core::auth::save"]
      #
      #   Command.new("core::auth::save").command => :"core::auth::save"
      #
      def initialize(cmd)
        cmdpath = sanitize_command_path(cmd).split('::')
        seq = cmdpath.inject(["*"]) { |list, cmd|
          list << (list.length > 1 ? list.last + "::" : "") + cmd
        }
        @path = seq.map { |k|
          k.to_sym
        }
        @command = path.last
        debug "Created command #{@command.inspect} with path #{@path.join(', ')}"
      end

      # Returs self
      def to_irc_auth_command
        self
      end

    end

  end

end


class String

  # Returns an Irc::Auth::Comand from the receiver
  def to_irc_auth_command
    Irc::Auth::Command.new(self)
  end

end


module Irc


  module Auth


    # This class describes a permission set
    class PermissionSet

      # Create a new (empty) PermissionSet
      #
      def initialize
        @perm = {}
      end

      # Inspection simply inspects the internal hash
      def inspect
        @perm.inspect
      end

      # Sets the permission for command _cmd_ to _val_,
      #
      def set_permission(str, val)
        cmd = str.to_irc_auth_command
        case val
        when true, false
          @perm[cmd.command] = val
        when nil
          @perm.delete(cmd.command)
        else
          raise TypeError, "#{val.inspect} must be true or false" unless [true,false].include?(val)
        end
      end

      # Resets the permission for command _cmd_
      #
      def reset_permission(cmd)
        set_permission(cmd, nil)
      end

      # Tells if command _cmd_ is permitted. We do this by returning
      # the value of the deepest Command#path that matches.
      #
      def permit?(str)
        cmd = str.to_irc_auth_command
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


    # This is the basic class for bot users: they have a username, a password,
    # a list of netmasks to match against, and a list of permissions.
    #
    class BotUser

      attr_reader :username
      attr_reader :password
      attr_reader :netmasks
      attr_writer :login_by_mask
      attr_writer :autologin

      # Create a new BotUser with given username
      def initialize(username)
        @username = BotUser.sanitize_username(username)
        @password = nil
        @netmasks = NetmaskList.new
        @perm = {}
        @login_by_mask = Auth.manager.bot.config['auth.login_by_mask'] unless defined?(@login_by_mask)
        @autologin = Auth.manager.bot.config['auth.autologin'] unless defined?(@autologin)
      end

      # Inspection
      def inspect
        str = "<#{self.class}:#{'0x%08x' % self.object_id}:"
        str << " @username=#{@username.inspect}"
        str << " @netmasks=#{@netmasks.inspect}"
        str << " @perm=#{@perm.inspect}"
        str << " @login_by_mask=#{@login_by_mask}"
        str << " @autologin=#{@autologin}"
        str << ">"
      end

      # Convert into a hash
      def to_hash
        {
          :username => @username,
          :password => @password,
          :netmasks => @netmasks,
          :perm => @perm,
          :login_by_mask => @login_by_mask,
          :autologin => @autologin
        }
      end

      # Do we allow logging in without providing the password?
      #
      def login_by_mask?
        @login_by_mask
      end

      # Do we allow automatic logging in?
      #
      def autologin?
        @autologin
      end

      # Restore from hash
      def from_hash(h)
        @username = h[:username] if h.has_key?(:username)
        @password = h[:password] if h.has_key?(:password)
        @netmasks = h[:netmasks] if h.has_key?(:netmasks)
        @perm = h[:perm] if h.has_key?(:perm)
        @login_by_mask = h[:login_by_mask] if h.has_key?(:login_by_mask)
        @autologin = h[:autologin] if h.has_key?(:autologin)
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

      # Resets the permission for command _cmd_ on channel _chan_
      #
      def reset_permission(cmd, chan ="*")
        set_permission(cmd, nil, chan)
      end

      # Checks if BotUser is allowed to do something on channel _chan_,
      # or on all channels if _chan_ is nil
      #
      def permit?(cmd, chan=nil)
        if chan
          k = chan.to_s.to_sym
        else
          k = :*
        end
        allow = nil
        if @perm.has_key?(k)
          allow = @perm[k].permit?(cmd)
        end
        return allow
      end

      # Adds a Netmask
      #
      def add_netmask(mask)
        @netmasks << mask.to_irc_netmask
      end

      # Removes a Netmask
      #
      def delete_netmask(mask)
        m = mask.to_irc_netmask
        @netmasks.delete(m)
      end

      # Removes all <code>Netmask</code>s
      #
      def reset_netmask_list
        @netmasks = NetmaskList.new
      end

      # This method checks if BotUser has a Netmask that matches _user_
      #
      def knows?(usr)
        user = usr.to_irc_user
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
        if password == @password or (password.nil? and (@login_by_mask || @autologin) and knows?(user))
          add_netmask(user) unless knows?(user)
          debug "#{user} logged in as #{self.inspect}"
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

    end


    # This is the default BotUser: it's used for all users which haven't
    # identified with the bot
    #
    class DefaultBotUserClass < BotUser

      private :login, :add_netmask, :delete_netmask

      include Singleton

      # The default BotUser is named 'everyone', it doesn't allow autologin
      # (meaningless) and it allows login-by-mask
      #
      def initialize
        @login_by_mask = true
        @autologin = false
        super("everyone")
        @default_perm = PermissionSet.new
      end

      # This method returns without changing anything
      #
      def login_by_mask=(val)
        debug "Tried to change the login-by-mask for default bot user, ignoring"
        return @login_by_mask
      end

      # This method returns without changing anything
      #
      def autologin=(val)
        debug "Tried to change the autologin for default bot user, ignoring"
        return
      end

      # Sets the default permission for the default user (i.e. the ones
      # set by the BotModule writers) on all channels
      #
      def set_default_permission(cmd, val)
        @default_perm.set_permission(Command.new(cmd), val)
        debug "Default permissions now:\n#{@default_perm.inspect}"
      end

      # default knows everybody
      #
      def knows?(user)
        return true if user.to_irc_user
      end

      # We always allow logging in as the default user
      def login(user, password)
        return true
      end

      # Resets the NetmaskList
      def reset_netmask_list
        super
        add_netmask("*!*@*")
      end

      # DefaultBotUser will check the default_perm after checking
      # the global ones
      # or on all channels if _chan_ is nil
      #
      def permit?(cmd, chan=nil)
        allow = super(cmd, chan)
        if allow.nil? && chan.nil?
          allow = @default_perm.permit?(cmd)
        end
        return allow
      end

    end

    # Returns the only instance of DefaultBotUserClass
    #
    def Auth.defaultbotuser
      return DefaultBotUserClass.instance
    end

    # This is the BotOwner: he can do everything
    #
    class BotOwnerClass < BotUser

      include Singleton

      def initialize
        @login_by_mask = false
        @autologin = false
        super("owner")
      end

      def permit?(cmd, chan=nil)
        return true
      end

    end

    # Returns the only instance of BotOwnerClass
    #
    def Auth.botowner
      return BotOwnerClass.instance
    end


    # This is the AuthManagerClass singleton, used to manage User/BotUser connections and
    # everything
    #
    class AuthManagerClass

      include Singleton

      attr_reader :everyone
      attr_reader :botowner

      # The instance manages two <code>Hash</code>es: one that maps
      # <code>Irc::User</code>s onto <code>BotUser</code>s, and the other that maps
      # usernames onto <code>BotUser</code>
      def initialize
        @everyone = Auth::defaultbotuser
        @botowner = Auth::botowner
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

      def set_changed
        @has_changes = true
      end

      def reset_changed
        @has_changes = false
      end

      def changed?
        @has_changes
      end

      # resets the hashes
      def reset_hashes
        @botusers = Hash.new
        @allbotusers = Hash.new
        [everyone, botowner].each { |x|
          @allbotusers[x.username.to_sym] = x
        }
      end

      def load_array(ary, forced)
        raise "Won't load with unsaved changes" if @has_changes and not forced
        reset_hashes
        ary.each { |x|
          raise TypeError, "#{x} should be a Hash" unless x.kind_of?(Hash)
          u = x[:username]
          unless include?(u)
            create_botuser(u)
          end
          get_botuser(u).from_hash(x)
        }
        @has_changes=false
      end

      def save_array
        @allbotusers.values.map { |x|
          x.to_hash
        }
      end

      # checks if we know about a certain BotUser username
      def include?(botusername)
        @allbotusers.has_key?(botusername.to_sym)
      end

      # Maps <code>Irc::User</code> to BotUser
      def irc_to_botuser(ircuser)
        # TODO check netmasks
        @botusers[ircuser.to_irc_user] || everyone
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

      # returns the botuser with name _name_
      def get_botuser(name)
        @allbotusers.fetch(BotUser.sanitize_username(name).to_sym)
      end

      # Logs Irc::User _user_ in to BotUser _botusername_ with password _pwd_
      #
      # raises an error if _botusername_ is not a known BotUser username
      #
      # It is possible to autologin by Netmask, on request
      #
      def login(user, botusername, pwd=nil)
        ircuser = user.to_irc_user
        n = BotUser.sanitize_username(botusername)
        k = n.to_sym
        raise "No such BotUser #{n}" unless include?(k)
        if @botusers.has_key?(ircuser)
          return true if @botusers[ircuser].name = n
          # TODO
          # @botusers[ircuser].logout(ircuser)
        end
        bu = @allbotusers[k]
        if bu.login(ircuser, pwd)
          @botusers[ircuser] = bu
          return true
        end
        return false
      end

      # Tries to auto-login Irc::User _user_ by looking at the known botusers that allow autologin
      # and trying to login without a password
      #
      def autologin(user)
        ircuser = user.to_irc_user
        debug "Trying to autlogin #{ircuser}"
        return @botusers[ircuser] if @botusers.has_key?(ircuser)
        @allbotusers.each { |n, bu|
          debug "Checking with #{n}"
          return bu if bu.autologin? and login(ircuser, n)
        }
        return everyone
      end

      # Checks if User _user_ can do _cmd_ on _chan_.
      #
      # Permission are checked in this order, until a true or false
      # is returned:
      # * associated BotUser on _chan_
      # * associated BotUser on all channels
      # * everyone on _chan_
      # * everyone on all channels
      #
      def permit?(user, cmdtxt, channel=nil)
        if user.class <= BotUser
          botuser = user
        else
          botuser = irc_to_botuser(user)
        end
        cmd = cmdtxt.to_irc_auth_command

        chan = channel
        case chan
        when User
          chan = "?"
        when Channel
          chan = chan.name
        end

        allow = nil

        allow = botuser.permit?(cmd, chan) if chan
        return allow unless allow.nil?
        allow = botuser.permit?(cmd)
        return allow unless allow.nil?

        unless botuser == everyone
          allow = everyone.permit?(cmd, chan) if chan
          return allow unless allow.nil?
          allow = everyone.permit?(cmd)
          return allow unless allow.nil?
        end

        raise "Could not check permission for user #{user.inspect} to run #{cmdtxt.inspect} on #{chan.inspect}"
      end

      # Checks if command _cmd_ is allowed to User _user_ on _chan_
      def allow?(cmdtxt, user, chan=nil)
        permit?(user, cmdtxt, chan)
      end

    end

    # Returns the only instance of AuthManagerClass
    #
    def Auth.authmanager
      return AuthManagerClass.instance
    end

  end

end
