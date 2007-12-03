#-- vim:sw=2:et
#++
# :title: User management
#
# rbot user management
# Author:: Giuseppe Bilotta (giuseppe.bilotta@gmail.com)
# Copyright:: Copyright (c) 2006 Giuseppe Bilotta
# License:: GPLv2

require 'singleton'
require 'set'
require 'rbot/maskdb'

# This would be a good idea if it was failproof, but the truth
# is that other methods can indirectly modify the hash. *sigh*
#
# class AuthNotifyingHash < Hash
#   %w(clear default= delete delete_if replace invert
#      merge! update rehash reject! replace shift []= store).each { |m|
#     class_eval {
#       define_method(m) { |*a|
#         r = super(*a)
#         Irc::Bot::Auth.manager.set_changed
#         r
#       }
#     }
#   }
# end
# 

module Irc
class Bot


  # This module contains the actual Authentication stuff
  #
  module Auth

    Config.register Config::StringValue.new( 'auth.password',
      :default => 'rbotauth', :wizard => true,
      :on_change => Proc.new {|bot, v| bot.auth.botowner.password = v},
      :desc => _('Password for the bot owner'))
    Config.register Config::BooleanValue.new( 'auth.login_by_mask',
      :default => 'true',
      :desc => _('Set false to prevent new botusers from logging in without a password when the user netmask is known'))
    Config.register Config::BooleanValue.new( 'auth.autologin',
      :default => 'true',
      :desc => _('Set false to prevent new botusers from recognizing IRC users without a need to manually login'))
    Config.register Config::BooleanValue.new( 'auth.autouser',
      :default => 'false',
      :desc => _('Set true to allow new botusers to be created automatically'))
    # Config.register Config::IntegerValue.new( 'auth.default_level',
    #   :default => 10, :wizard => true,
    #   :desc => 'The default level for new/unknown users' )

    # Generate a random password of length _l_
    #
    def Auth.random_password(l=8)
      pwd = ""
      l.times do
        pwd << (rand(26) + (rand(2) == 0 ? 65 : 97) ).chr
      end
      return pwd
    end


    # An Irc::Bot::Auth::Command defines a command by its "path":
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
        debug "Created command #{@command.inspect} with path #{@path.pretty_inspect}"
      end

      # Returs self
      def to_irc_auth_command
        self
      end

    end

  end

end
end


class String

  # Returns an Irc::Bot::Auth::Comand from the receiver
  def to_irc_auth_command
    Irc::Bot::Auth::Command.new(self)
  end

end


class Symbol

  # Returns an Irc::Bot::Auth::Comand from the receiver
  def to_irc_auth_command
    Irc::Bot::Auth::Command.new(self)
  end

end


module Irc
class Bot


  module Auth


    # This class describes a permission set
    class PermissionSet

      attr_reader :perm
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
        # TODO user-configurable list of always-allowed commands,
        # for admins that want to set permissions -* for everybody
        return true if cmd.command == :login
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


    # This is the error that gets raised when an invalid password is met
    #
    class InvalidPassword < RuntimeError
    end


    # This is the basic class for bot users: they have a username, a
    # password, a list of netmasks to match against, and a list of
    # permissions. A BotUser can be marked as 'transient', usually meaning
    # it's not intended for permanent storage. Transient BotUsers have lower
    # priority than nontransient ones for autologin purposes.
    #
    # To initialize a BotUser, you pass a _username_ and an optional
    # hash of options. Currently, only two options are recognized:
    #
    # transient:: true or false, determines if the BotUser is transient or
    #             permanent (default is false, permanent BotUser).
    #
    #             Transient BotUsers are initialized by prepending an
    #             asterisk (*) to the username, and appending a sanitized
    #             version of the object_id. The username can be empty.
    #             A random password is generated.
    #
    #             Permanent Botusers need the username as is, and no
    #             password is generated.
    #
    # masks::     an array of Netmasks to initialize the NetmaskList. This
    #             list is used as-is for permanent BotUsers.
    #
    #             Transient BotUsers will alter the list elements which are
    #             Irc::User by globbing the nick and any initial nonletter
    #             part of the ident.
    #
    #             The masks option is optional for permanent BotUsers, but
    #             obligatory (non-empty) for transients.
    #
    class BotUser

      attr_reader :username
      attr_reader :password
      attr_reader :netmasks
      attr_reader :perm
      attr_writer :login_by_mask
      attr_writer :transient

      def autologin=(vnew)
        vold = @autologin
        @autologin = vnew
        if vold && !vnew
          @netmasks.each { |n| Auth.manager.maskdb.remove(self, n) }
        elsif vnew && !vold
          @netmasks.each { |n| Auth.manager.maskdb.add(self, n) }
        end
      end

      # Checks if the BotUser is transient
      def transient?
        @transient
      end

      # Checks if the BotUser is permanent (not transient)
      def permanent?
        !@transient
      end

      # Sets if the BotUser is permanent or not
      def permanent=(bool)
        @transient=!bool
      end

      # Make the BotUser permanent
      def make_permanent(name)
        raise TypeError, "permanent already" if permanent?
        @username = BotUser.sanitize_username(name)
        @transient = false
        reset_autologin
        reset_password # or not?
        @netmasks.dup.each do |m|
          delete_netmask(m)
          add_netmask(m.generalize)
        end
      end

      # Create a new BotUser with given username
      def initialize(username, options={})
        opts = {:transient => false}.merge(options)
        @transient = opts[:transient]

        if @transient
          @username = "*"
          @username << BotUser.sanitize_username(username) if username and not username.to_s.empty?
          @username << BotUser.sanitize_username(object_id)
          reset_password
          @login_by_mask=true
          @autologin=true
        else
          @username = BotUser.sanitize_username(username)
          @password = nil
          reset_login_by_mask
          reset_autologin
        end

        @netmasks = NetmaskList.new
        if opts.key?(:masks) and opts[:masks]
          masks = opts[:masks]
          masks = [masks] unless masks.respond_to?(:each)
          masks.each { |m|
            mask = m.to_irc_netmask
            if @transient and User === m
              mask.nick = "*"
              mask.host = m.host.dup
              mask.user = "*" + m.user.sub(/^\w?[^\w]+/,'')
            end
            add_netmask(mask) unless mask.to_s == "*"
          }
        end
        raise "must provide a usable mask for transient BotUser #{@username}" if @transient and @netmasks.empty?

        @perm = {}
      end

      # Inspection
      def inspect
        str = self.__to_s__[0..-2]
        str << " (transient)" if @transient
        str << ":"
        str << " @username=#{@username.inspect}"
        str << " @netmasks=#{@netmasks.inspect}"
        str << " @perm=#{@perm.inspect}"
        str << " @login_by_mask=#{@login_by_mask}"
        str << " @autologin=#{@autologin}"
        str << ">"
      end

      # In strings
      def to_s
        @username
      end

      # Convert into a hash
      def to_hash
        {
          :username => @username,
          :password => @password,
          :netmasks => @netmasks,
          :perm => @perm,
          :login_by_mask => @login_by_mask,
          :autologin => @autologin,
        }
      end

      # Do we allow logging in without providing the password?
      #
      def login_by_mask?
        @login_by_mask
      end

      # Reset the login-by-mask option
      #
      def reset_login_by_mask
        @login_by_mask = Auth.manager.bot.config['auth.login_by_mask'] unless defined?(@login_by_mask)
      end

      # Reset the autologin option
      #
      def reset_autologin
        @autologin = Auth.manager.bot.config['auth.autologin'] unless defined?(@autologin)
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
        @login_by_mask = h[:login_by_mask] if h.has_key?(:login_by_mask)
        @autologin = h[:autologin] if h.has_key?(:autologin)
        if h.has_key?(:netmasks)
          @netmasks = h[:netmasks]
          @netmasks.each { |n| Auth.manager.maskdb.add(self, n) } if @autologin
        end
        @perm = h[:perm] if h.has_key?(:perm)
      end

      # This method sets the password if the proposed new password
      # is valid
      def password=(pwd=nil)
        pass = pwd.to_s
        if pass.empty?
          reset_password
        else
          begin
            raise InvalidPassword, "#{pass} contains invalid characters" if pass !~ /^[\x21-\x7e]+$/
            raise InvalidPassword, "#{pass} too short" if pass.length < 4
            @password = pass
          rescue InvalidPassword => e
            raise e
          rescue => e
            raise InvalidPassword, "Exception #{e.inspect} while checking #{pass.inspect} (#{pwd.inspect})"
          end
        end
      end

      # Resets the password by creating a new onw
      def reset_password
        @password = Auth.random_password
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
        m = mask.to_irc_netmask
        @netmasks << m
        if self.autologin?
          Auth.manager.maskdb.add(self, m)
          Auth.manager.logout_transients(m) if self.permanent?
        end
      end

      # Removes a Netmask
      #
      def delete_netmask(mask)
        m = mask.to_irc_netmask
        @netmasks.delete(m)
        Auth.manager.maskdb.remove(self, m) if self.autologin?
      end

      # This method checks if BotUser has a Netmask that matches _user_
      #
      def knows?(usr)
        user = usr.to_irc_user
        !!@netmasks.find { |n| user.matches? n }
      end

      # This method gets called when User _user_ wants to log in.
      # It returns true or false depending on whether the password
      # is right. If it is, the Netmask of the user is added to the
      # list of acceptable Netmask unless it's already matched.
      def login(user, password=nil)
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
        candidate = name.to_s.chomp.downcase.gsub(/[^a-z0-9]/,"_")
        raise "sanitized botusername #{candidate} too short" if candidate.length < 3
        return candidate
      end

    end

    # This is the default BotUser: it's used for all users which haven't
    # identified with the bot
    #
    class DefaultBotUserClass < BotUser

      private :add_netmask, :delete_netmask

      include Singleton

      # The default BotUser is named 'everyone'
      #
      def initialize
        reset_login_by_mask
        reset_autologin
        super("everyone")
        @default_perm = PermissionSet.new
      end

      # This method returns without changing anything
      #
      def login_by_mask=(val)
        debug "Tried to change the login-by-mask for default bot user, ignoring"
        return @login_by_mask
      end

      # The default botuser allows logins by mask
      #
      def reset_login_by_mask
        @login_by_mask = true
      end

      # This method returns without changing anything
      #
      def autologin=(val)
        debug "Tried to change the autologin for default bot user, ignoring"
        return
      end

      # The default botuser doesn't allow autologin (meaningless)
      #
      def reset_autologin
        @autologin = false
      end

      # Sets the default permission for the default user (i.e. the ones
      # set by the BotModule writers) on all channels
      #
      def set_default_permission(cmd, val)
        @default_perm.set_permission(Command.new(cmd), val)
        debug "Default permissions now: #{@default_perm.pretty_inspect}"
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
        @autologin = true
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


    class BotUser
      # Check if the current BotUser is the default one
      def default?
        return DefaultBotUserClass === self
      end

      # Check if the current BotUser is the owner
      def owner?
        return BotOwnerClass === self
      end
    end


    # This is the ManagerClass singleton, used to manage
    # Irc::User/Irc::Bot::Auth::BotUser connections and everything
    #
    class ManagerClass

      include Singleton

      attr_reader :maskdb
      attr_reader :everyone
      attr_reader :botowner
      attr_reader :bot

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
        @maskdb = NetmaskDb.new
        @allbotusers = Hash.new
        [everyone, botowner].each do |x|
          @allbotusers[x.username.to_sym] = x
        end
      end

      def load_array(ary, forced)
        unless ary
          warning "Tried to load an empty array"
          return
        end
        raise "Won't load with unsaved changes" if @has_changes and not forced
        reset_hashes
        ary.each { |x|
          raise TypeError, "#{x} should be a Hash" unless x.kind_of?(Hash)
          u = x[:username]
          unless include?(u)
            create_botuser(u)
          end
          get_botuser(u).from_hash(x)
          get_botuser(u).transient = false
        }
        @has_changes=false
      end

      def save_array
        @allbotusers.values.map { |x|
          x.transient? ? nil : x.to_hash
        }.compact
      end

      # checks if we know about a certain BotUser username
      def include?(botusername)
        @allbotusers.has_key?(botusername.to_sym)
      end

      # Maps <code>Irc::User</code> to BotUser
      def irc_to_botuser(ircuser)
        logged = @botusers[ircuser.to_irc_user]
        return logged if logged
        return autologin(ircuser)
      end

      # creates a new BotUser
      def create_botuser(name, password=nil)
        n = BotUser.sanitize_username(name)
        k = n.to_sym
        raise "botuser #{n} exists" if include?(k)
        bu = BotUser.new(n)
        bu.password = password
        @allbotusers[k] = bu
        return bu
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
          return true if @botusers[ircuser].username == n
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
        debug "Trying to autologin #{ircuser}"
        return @botusers[ircuser] if @botusers.has_key?(ircuser)
        bu = maskdb.find(ircuser)
        if bu
          debug "trying #{bu}"
          bu.login(ircuser) or raise '...what?!'
          @botusers[ircuser] = bu
          return bu
        end
        # Finally, create a transient if we're set to allow it
        if @bot.config['auth.autouser']
          bu = create_transient_botuser(ircuser)
          @botusers[ircuser] = bu
          return bu
        end
        return everyone
      end

      # Creates a new transient BotUser associated with Irc::User _user_,
      # automatically logging him in. Note that transient botuser creation can
      # fail, typically if we don't have the complete user netmask (e.g. for
      # messages coming in from a linkbot)
      #
      def create_transient_botuser(user)
        ircuser = user.to_irc_user
        bu = everyone
        begin
          bu = BotUser.new(ircuser, :transient => true, :masks => ircuser)
          bu.login(ircuser)
        rescue
          warning "failed to create transient for #{user}"
          error $!
        end
        return bu
      end

      # Logs out any Irc::User matching Irc::Netmask _m_ and logged in
      # to a transient BotUser
      #
      def logout_transients(m)
        debug "to check: #{@botusers.keys.join ' '}"
        @botusers.keys.each do |iu|
          debug "checking #{iu.fullform} against #{m.fullform}"
          bu = @botusers[iu]
          bu.transient? or next
          iu.matches?(m) or next
          @botusers.delete(iu).autologin = false
        end
      end

      # Makes transient BotUser _user_ into a permanent BotUser
      # named _name_; if _user_ is an Irc::User, act on the transient
      # BotUser (if any) it's logged in as
      #
      def make_permanent(user, name)
        buname = BotUser.sanitize_username(name)
        # TODO merge BotUser instead?
        raise "there's already a BotUser called #{name}" if include?(buname)

        tuser = nil
        case user
        when String, Irc::User
          tuser = irc_to_botuser(user)
        when BotUser
          tuser = user
        else
          raise TypeError, "sorry, don't know how to make #{user.class} into a permanent BotUser"
        end
        return nil unless tuser
        raise TypeError, "#{tuser} is not transient" unless tuser.transient?

        tuser.make_permanent(buname)
        @allbotusers[tuser.username.to_sym] = tuser

        return tuser
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

      # Checks if command _cmd_ is allowed to User _user_ on _chan_, optionally
      # telling if the user is authorized
      #
      def allow?(cmdtxt, user, chan=nil)
        if permit?(user, cmdtxt, chan)
          return true
        else
          # cmds = cmdtxt.split('::')
          # @bot.say chan, "you don't have #{cmds.last} (#{cmds.first}) permissions here" if chan
          @bot.say chan, _("%{user}, you don't have '%{command}' permissions here") %
                        {:user=>user, :command=>cmdtxt} if chan
          return false
        end
      end

    end

    # Returns the only instance of ManagerClass
    #
    def Auth.manager
      return ManagerClass.instance
    end

  end
end

  class User

    # A convenience method to automatically found the botuser
    # associated with the receiver
    #
    def botuser
      Irc::Bot::Auth.manager.irc_to_botuser(self)
    end
  end

end
