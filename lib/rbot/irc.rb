#-- vim:sw=2:et
# General TODO list
# * do we want to handle a Channel list for each User telling which
#   Channels is the User on (of those the client is on too)?
#   We may want this so that when a User leaves all Channels and he hasn't
#   sent us privmsgs, we know remove him from the Server @users list
#++
# :title: IRC module
#
# Basic IRC stuff
#
# This module defines the fundamental building blocks for IRC
#
# Author:: Giuseppe Bilotta (giuseppe.bilotta@gmail.com)
# Copyright:: Copyright (c) 2006 Giuseppe Bilotta
# License:: GPLv2


# We start by extending the String class
# with some IRC-specific methods
#
class String

  # This method returns a string which is the downcased version of the
  # receiver, according to IRC rules: due to the Scandinavian origin of IRC,
  # the characters <tt>{}|^</tt> are considered the uppercase equivalent of
  # <tt>[]\~</tt>.
  #
  # Since IRC is mostly case-insensitive (the Windows way: case is preserved,
  # but it's actually ignored to check equality), this method is rather
  # important when checking if two strings refer to the same entity
  # (User/Channel)
  #
  # Modern server allow different casemaps, too, in which some or all
  # of the extra characters are not converted
  #
  def irc_downcase(casemap='rfc1459')
    case casemap
    when 'rfc1459'
      self.tr("\x41-\x5e", "\x61-\x7e")
    when 'strict-rfc1459'
      self.tr("\x41-\x5d", "\x61-\x7d")
    when 'ascii'
      self.tr("\x41-\x5a", "\x61-\x7a")
    else
      raise TypeError, "Unknown casemap #{casemap}"
    end
  end

  # This is the same as the above, except that the string is altered in place
  #
  # See also the discussion about irc_downcase
  #
  def irc_downcase!(casemap='rfc1459')
    case casemap
    when 'rfc1459'
      self.tr!("\x41-\x5e", "\x61-\x7e")
    when 'strict-rfc1459'
      self.tr!("\x41-\x5d", "\x61-\x7d")
    when 'ascii'
      self.tr!("\x41-\x5a", "\x61-\x7a")
    else
      raise TypeError, "Unknown casemap #{casemap}"
    end
  end

  # Upcasing functions are provided too
  #
  # See also the discussion about irc_downcase
  #
  def irc_upcase(casemap='rfc1459')
    case casemap
    when 'rfc1459'
      self.tr("\x61-\x7e", "\x41-\x5e")
    when 'strict-rfc1459'
      self.tr("\x61-\x7d", "\x41-\x5d")
    when 'ascii'
      self.tr("\x61-\x7a", "\x41-\x5a")
    else
      raise TypeError, "Unknown casemap #{casemap}"
    end
  end

  # In-place upcasing
  #
  # See also the discussion about irc_downcase
  #
  def irc_upcase!(casemap='rfc1459')
    case casemap
    when 'rfc1459'
      self.tr!("\x61-\x7e", "\x41-\x5e")
    when 'strict-rfc1459'
      self.tr!("\x61-\x7d", "\x41-\x5d")
    when 'ascii'
      self.tr!("\x61-\x7a", "\x41-\x5a")
    else
      raise TypeError, "Unknown casemap #{casemap}"
    end
  end

  # This method checks if the receiver contains IRC glob characters
  #
  # IRC has a very primitive concept of globs: a <tt>*</tt> stands for "any
  # number of arbitrary characters", a <tt>?</tt> stands for "one and exactly
  # one arbitrary character". These characters can be escaped by prefixing them
  # with a slash (<tt>\\</tt>).
  #
  # A known limitation of this glob syntax is that there is no way to escape
  # the escape character itself, so it's not possible to build a glob pattern
  # where the escape character precedes a glob.
  #
  def has_irc_glob?
    self =~ /^[*?]|[^\\][*?]/
  end

  # This method is used to convert the receiver into a Regular Expression
  # that matches according to the IRC glob syntax
  #
  def to_irc_regexp
    regmask = Regexp.escape(self)
    regmask.gsub!(/(\\\\)?\\[*?]/) { |m|
      case m
      when /\\(\\[*?])/
        $1
      when /\\\*/
        '.*'
      when /\\\?/
        '.'
      else
        raise "Unexpected match #{m} when converting #{self}"
      end
    }
    Regexp.new(regmask)
  end
end


# ArrayOf is a subclass of Array whose elements are supposed to be all
# of the same class. This is not intended to be used directly, but rather
# to be subclassed as needed (see for example Irc::UserList and Irc::NetmaskList)
#
# Presently, only very few selected methods from Array are overloaded to check
# if the new elements are the correct class. An orthodox? method is provided
# to check the entire ArrayOf against the appropriate class.
#
class ArrayOf < Array

  attr_reader :element_class

  # Create a new ArrayOf whose elements are supposed to be all of type _kl_,
  # optionally filling it with the elements from the Array argument.
  #
  def initialize(kl, ar=[])
    raise TypeError, "#{kl.inspect} must be a class name" unless kl.class <= Class
    super()
    @element_class = kl
    case ar
    when Array
      send(:+, ar)
    else
      raise TypeError, "#{self.class} can only be initialized from an Array"
    end
  end

  # Private method to check the validity of the elements passed to it
  # and optionally raise an error
  #
  # TODO should it accept nils as valid?
  #
  def internal_will_accept?(raising, *els)
    els.each { |el|
      unless el.class <= @element_class
        raise TypeError if raising
        return false
      end
    }
    return true
  end
  private :internal_will_accept?

  # This method checks if the passed arguments are acceptable for our ArrayOf
  #
  def will_accept?(*els)
    internal_will_accept?(false, *els)
  end

  # This method checks that all elements are of the appropriate class
  #
  def valid?
    will_accept?(*self)
  end

  # This method is similar to the above, except that it raises an exception
  # if the receiver is not valid
  def validate
    raise TypeError unless valid?
  end

  # Overloaded from Array#<<, checks for appropriate class of argument
  #
  def <<(el)
    super(el) if internal_will_accept?(true, el)
  end

  # Overloaded from Array#unshift, checks for appropriate class of argument(s)
  #
  def unshift(*els)
    els.each { |el|
      super(el) if internal_will_accept?(true, *els)
    }
  end

  # Overloaded from Array#+, checks for appropriate class of argument elements
  #
  def +(ar)
    super(ar) if internal_will_accept?(true, *ar)
  end
end

# The Irc module is used to keep all IRC-related classes
# in the same namespace
#
module Irc


  # A Netmask identifies each user by collecting its nick, username and
  # hostname in the form <tt>nick!user@host</tt>
  #
  # Netmasks can also contain glob patterns in any of their components; in this
  # form they are used to refer to more than a user or to a user appearing
  # under different
  # forms.
  #
  # Example:
  # * <tt>*!*@*</tt> refers to everybody
  # * <tt>*!someuser@somehost</tt> refers to user +someuser+ on host +somehost+
  #   regardless of the nick used.
  #
  class Netmask
    attr_reader :nick, :user, :host
    attr_reader :casemap

    # call-seq:
    #   Netmask.new(netmask) => new_netmask
    #   Netmask.new(hash={}, casemap=nil) => new_netmask
    #   Netmask.new("nick!user@host", casemap=nil) => new_netmask
    #
    # Create a new Netmask in any of these forms
    # 1. from another Netmask (does a .dup)
    # 2. from a Hash with any of the keys <tt>:nick</tt>, <tt>:user</tt> and
    #    <tt>:host</tt>
    # 3. from a String in the form <tt>nick!user@host</tt>
    #
    # In all but the first forms a casemap may be speficied, the default
    # being 'rfc1459'.
    #
    # The nick is downcased following IRC rules and according to the given casemap.
    #
    # FIXME check if user and host need to be downcased too.
    #
    # Empty +nick+, +user+ or +host+ are converted to the generic glob pattern
    #
    def initialize(str={}, casemap=nil)
      case str
      when Netmask
        raise ArgumentError, "Can't set casemap when initializing from other Netmask" if casemap
        @casemap = str.casemap.dup
        @nick = str.nick.dup
        @user = str.user.dup
        @host = str.host.dup
      when Hash
        @casemap = casemap || str[:casemap] || 'rfc1459'
        @nick = str[:nick].to_s.irc_downcase(@casemap)
        @user = str[:user].to_s
        @host = str[:host].to_s
      when String
        case str
        when ""
          @casemap = casemap || 'rfc1459'
          @nick = nil
          @user = nil
          @host = nil
        when /(\S+)(?:!(\S+)@(?:(\S+))?)?/
          @casemap = casemap || 'rfc1459'
          @nick = $1.irc_downcase(@casemap)
          @user = $2
          @host = $3
        else
          raise ArgumentError, "#{str} is not a valid netmask"
        end
      else
        raise ArgumentError, "#{str} is not a valid netmask"
      end

      @nick = "*" if @nick.to_s.empty?
      @user = "*" if @user.to_s.empty?
      @host = "*" if @host.to_s.empty?
    end

    # This method changes the nick of the Netmask, downcasing the argument
    # following IRC rules and defaulting to the generic glob pattern if
    # the result is the null string.
    #
    def nick=(newnick)
      @nick = newnick.to_s.irc_downcase(@casemap)
      @nick = "*" if @nick.empty?
    end

    # This method changes the user of the Netmask, defaulting to the generic
    # glob pattern if the result is the null string.
    #
    def user=(newuser)
      @user = newuser.to_s
      @user = "*" if @user.empty?
    end

    # This method changes the hostname of the Netmask, defaulting to the generic
    # glob pattern if the result is the null string.
    #
    def host=(newhost)
      @host = newhost.to_s
      @host = "*" if @host.empty?
    end

    # This method checks if a Netmask is definite or not, by seeing if
    # any of its components are defined by globs
    #
    def has_irc_glob?
      return @nick.has_irc_glob? || @user.has_irc_glob? || @host.has_irc_glob?
    end

    # A Netmask is easily converted to a String for the usual representation
    # 
    def fullform
      return "#{nick}@#{user}!#{host}"
    end
    alias :to_s :fullform

    # This method is used to match the current Netmask against another one
    #
    # The method returns true if each component of the receiver matches the
    # corresponding component of the argument. By _matching_ here we mean that
    # any netmask described by the receiver is also described by the argument.
    #
    # In this sense, matching is rather simple to define in the case when the
    # receiver has no globs: it is just necessary to check if the argument
    # describes the receiver, which can be done by matching it against the
    # argument converted into an IRC Regexp (see String#to_irc_regexp).
    #
    # The situation is also easy when the receiver has globs and the argument
    # doesn't, since in this case the result is false.
    #
    # The more complex case in which both the receiver and the argument have
    # globs is not handled yet.
    # 
    def matches?(arg)
      cmp = Netmask(arg)
      raise TypeError, "#{arg} and #{self} have different casemaps" if @casemap != cmp.casemap
      raise TypeError, "#{arg} is not a valid Netmask" unless cmp.class <= Netmask
      [:nick, :user, :host].each { |component|
        us = self.send(:component)
        them = cmp.send(:component)
        raise NotImplementedError if us.has_irc_glob? && them.has_irc_glob?
        return false if us.has_irc_glob? && !them.has_irc_glob?
        return false unless us =~ them.to_irc_regexp
      }
      return true
    end

    # Case equality. Checks if arg matches self
    #
    def ===(arg)
      Netmask(arg).matches?(self)
    end
  end


  # A NetmaskList is an ArrayOf <code>Netmask</code>s
  #
  class NetmaskList < ArrayOf

    # Create a new NetmaskList, optionally filling it with the elements from
    # the Array argument fed to it.
    def initialize(ar=[])
      super(Netmask, ar)
    end
  end


  # An IRC User is identified by his/her Netmask (which must not have
  # globs). In fact, User is just a subclass of Netmask. However,
  # a User will not allow one's host or user data to be changed.
  #
  # Due to the idiosincrasies of the IRC protocol, we allow
  # the creation of a user with an unknown mask represented by the
  # glob pattern *@*. Only in this case they may be set.
  #
  # TODO list:
  # * see if it's worth to add the other USER data
  # * see if it's worth to add NICKSERV status
  #
  class User < Netmask
    alias :to_s :nick

    # Create a new IRC User from a given Netmask (or anything that can be converted
    # into a Netmask) provided that the given Netmask does not have globs.
    #
    def initialize(str="", casemap=nil)
      super
      raise ArgumentError, "#{str.inspect} must not have globs (unescaped * or ?)" if nick.has_irc_glob? && nick != "*"
      raise ArgumentError, "#{str.inspect} must not have globs (unescaped * or ?)" if user.has_irc_glob? && user != "*"
      raise ArgumentError, "#{str.inspect} must not have globs (unescaped * or ?)" if host.has_irc_glob? && host != "*"
      @away = false
    end

    # We only allow the user to be changed if it was "*". Otherwise,
    # we raise an exception if the new host is different from the old one
    #
    def user=(newuser)
      if user == "*"
        super
      else
        raise "Can't change the username of user #{self}" if user != newuser
      end
    end

    # We only allow the host to be changed if it was "*". Otherwise,
    # we raise an exception if the new host is different from the old one
    #
    def host=(newhost)
      if host == "*"
        super
      else
        raise "Can't change the hostname of user #{self}" if host != newhost 
      end
    end

    # Checks if a User is well-known or not by looking at the hostname and user
    #
    def known?
      return user!="*" && host!="*"
    end

    # Is the user away?
    #
    def away?
      return @away
    end

    # Set the away status of the user. Use away=(nil) or away=(false)
    # to unset away
    #
    def away=(msg="")
      if msg
        @away = msg
      else
        @away = false
      end
    end
  end


  # A UserList is an ArrayOf <code>User</code>s
  #
  class UserList < ArrayOf

    # Create a new UserList, optionally filling it with the elements from
    # the Array argument fed to it.
    def initialize(ar=[])
      super(User, ar)
    end
  end


  # A ChannelTopic represents the topic of a channel. It consists of
  # the topic itself, who set it and when
  class ChannelTopic
    attr_accessor :text, :set_by, :set_on
    alias :to_s :text

    # Create a new ChannelTopic setting the text, the creator and
    # the creation time
    def initialize(text="", set_by="", set_on=Time.new)
      @text = text
      @set_by = set_by
      @set_on = Time.new
    end
  end


  # Mode on a channel
  class ChannelMode
  end


  # Channel modes of type A manipulate lists
  #
  class ChannelModeTypeA < ChannelMode
    def initialize
      @list = NetmaskList.new
    end

    def set(val)
      @list << val unless @list.include?(val)
    end

    def reset(val)
      @list.delete(val)
    end
  end

  # Channel modes of type B need an argument
  #
  class ChannelModeTypeB < ChannelMode
    def initialize
      @arg = nil
    end

    def set(val)
      @arg = val
    end

    def reset(val)
      @arg = nil if @arg == val
    end
  end

  # Channel modes that change the User prefixes are like
  # Channel modes of type B, except that they manipulate
  # lists of Users, so they are somewhat similar to channel
  # modes of type A
  #
  class ChannelUserMode < ChannelModeTypeB
    def initialize
      @list = UserList.new
    end

    def set(val)
      @list << val unless @list.include?(val)
    end

    def reset(val)
      @list.delete(val)
    end
  end

  # Channel modes of type C need an argument when set,
  # but not when they get reset
  #
  class ChannelModeTypeC < ChannelMode
    def initialize
      @arg = false
    end

    def set(val)
      @arg = val
    end

    def reset
      @arg = false
    end
  end

  # Channel modes of type D are basically booleans
  class ChannelModeTypeD
    def initialize
      @set = false
    end

    def set?
      return @set
    end

    def set
      @set = true
    end

    def reset
      @set = false
    end
  end


  # An IRC Channel is identified by its name, and it has a set of properties:
  # * a topic
  # * a UserList
  # * a set of modes
  #
  class Channel
    attr_reader :name, :topic, :casemap, :mode, :users
    alias :to_s :name

    # A String describing the Channel and (some of its) internals
    #
    def inspect
      str = "<#{self.class}:#{'0x%08x' % self.object_id}:"
      str << " @name=#{@name.inspect} @topic=#{@topic.text.inspect}"
      str << " @users=<#{@users.join(', ')}>"
      str
    end

    # Creates a new channel with the given name, optionally setting the topic
    # and an initial users list.
    #
    # No additional info is created here, because the channel flags and userlists
    # allowed depend on the server.
    #
    # FIXME doesn't check if users have the same casemap as the channel yet
    #
    def initialize(name, topic=nil, users=[], casemap=nil)
      @casemap = casemap || 'rfc1459'

      raise ArgumentError, "Channel name cannot be empty" if name.to_s.empty?
      raise ArgumentError, "Unknown channel prefix #{name[0].chr}" if name !~ /^[&#+!]/
      raise ArgumentError, "Invalid character in #{name.inspect}" if name =~ /[ \x07,]/

      @name = name.irc_downcase(@casemap)

      @topic = topic || ChannelTopic.new

      case users
      when UserList
        @users = users
      when Array
        @users = UserList.new(users)
      else
        raise ArgumentError, "Invalid user list #{users.inspect}"
      end

      # Flags
      @mode = {}
    end

    # Removes a user from the channel
    #
    def delete_user(user)
      @mode.each { |sym, mode|
        mode.reset(user) if mode.class <= ChannelUserMode
      }
      @users.delete(user)
    end

    # The channel prefix
    #
    def prefix
      name[0].chr
    end

    # A channel is local to a server if it has the '&' prefix
    #
    def local?
      name[0] = 0x26
    end

    # A channel is modeless if it has the '+' prefix
    #
    def modeless?
      name[0] = 0x2b
    end

    # A channel is safe if it has the '!' prefix
    #
    def safe?
      name[0] = 0x21
    end

    # A channel is safe if it has the '#' prefix
    #
    def normal?
      name[0] = 0x23
    end

    # Create a new mode
    #
    def create_mode(sym, kl)
      @mode[sym.to_sym] = kl.new
    end
  end


  # A ChannelList is an ArrayOf <code>Channel</code>s
  #
  class ChannelList < ArrayOf

    # Create a new ChannelList, optionally filling it with the elements from
    # the Array argument fed to it.
    def initialize(ar=[])
      super(Channel, ar)
    end
  end


  # An IRC Server represents the Server the client is connected to.
  #
  class Server

    attr_reader :hostname, :version, :usermodes, :chanmodes
    alias :to_s :hostname
    attr_reader :supports, :capabilities

    attr_reader :channels, :users

    # Create a new Server, with all instance variables reset
    # to nil (for scalar variables), the channel and user lists
    # are empty, and @supports is initialized to the default values
    # for all known supported features.
    #
    def initialize
      @hostname = @version = @usermodes = @chanmodes = nil

      @channels = ChannelList.new
      @channel_names = Array.new

      @users = UserList.new
      @user_nicks = Array.new

      reset_capabilities
    end

    # Resets the server capabilities
    #
    def reset_capabilities
      @supports = {
        :casemapping => 'rfc1459',
        :chanlimit => {},
        :chanmodes => {
          :typea => nil, # Type A: address lists
          :typeb => nil, # Type B: needs a parameter
          :typec => nil, # Type C: needs a parameter when set
          :typed => nil  # Type D: must not have a parameter
        },
        :channellen => 200,
        :chantypes => "#&",
        :excepts => nil,
        :idchan => {},
        :invex => nil,
        :kicklen => nil,
        :maxlist => {},
        :modes => 3,
        :network => nil,
        :nicklen => 9,
        :prefix => {
          :modes => 'ov'.scan(/./),
          :prefixes => '@+'.scan(/./)
        },
        :safelist => nil,
        :statusmsg => nil,
        :std => nil,
        :targmax => {},
        :topiclen => nil
      }
      @capabilities = {}
    end

    # Resets the Channel and User list
    #
    def reset_lists
      @users.each { |u|
        delete_user(u)
      }
      @channels.each { |u|
        delete_channel(u)
      }
    end

    # Clears the server
    #
    def clear
      reset_lists
      reset_capabilities
    end

    # This method is used to parse a 004 RPL_MY_INFO line
    #
    def parse_my_info(line)
      ar = line.split(' ')
      @hostname = ar[0]
      @version = ar[1]
      @usermodes = ar[2]
      @chanmodes = ar[3]
    end

    def noval_warn(key, val, &block)
      if val
        yield if block_given?
      else
        warn "No #{key.to_s.upcase} value"
      end
    end

    def val_warn(key, val, &block)
      if val == true or val == false or val.nil?
        yield if block_given?
      else
        warn "No #{key.to_s.upcase} value must be specified, got #{val}"
      end
    end
    private :noval_warn, :val_warn

    # This method is used to parse a 005 RPL_ISUPPORT line
    #
    # See the RPL_ISUPPORT draft[http://www.irc.org/tech_docs/draft-brocklesby-irc-isupport-03.txt]
    #
    def parse_isupport(line)
      ar = line.split(' ')
      reparse = ""
      ar.each { |en|
        prekey, val = en.split('=', 2)
        if prekey =~ /^-(.*)/
          key = $1.downcase.to_sym
          val = false
        else
          key = prekey.downcase.to_sym
        end
        case key
        when :casemapping, :network
          noval_warn(key, val) {
            @supports[key] = val
          }
        when :chanlimit, :idchan, :maxlist, :targmax
          noval_warn(key, val) {
            groups = val.split(',')
            groups.each { |g|
              k, v = g.split(':')
              @supports[key][k] = v.to_i
            }
          }
        when :maxchannels
          noval_warn(key, val) {
            reparse += "CHANLIMIT=(chantypes):#{val} "
          }
        when :maxtargets
          noval_warn(key, val) {
            @supports[key]['PRIVMSG'] = val.to_i
            @supports[key]['NOTICE'] = val.to_i
          }
        when :chanmodes
          noval_warn(key, val) {
            groups = val.split(',')
            @supports[key][:typea] = groups[0].scan(/./)
            @supports[key][:typeb] = groups[1].scan(/./)
            @supports[key][:typec] = groups[2].scan(/./)
            @supports[key][:typed] = groups[3].scan(/./)
          }
        when :channellen, :kicklen, :modes, :topiclen
          if val
            @supports[key] = val.to_i
          else
            @supports[key] = nil
          end
        when :chantypes
          @supports[key] = val # can also be nil
        when :excepts
          val ||= 'e'
          @supports[key] = val
        when :invex
          val ||= 'I'
          @supports[key] = val
        when :nicklen
          noval_warn(key, val) {
            @supports[key] = val.to_i
          }
        when :prefix
          if val
            val.scan(/\((.*)\)(.*)/) { |m, p|
              @supports[key][:modes] = m.scan(/./)
              @supports[key][:prefixes] = p.scan(/./)
            }
          else
            @supports[key][:modes] = nil
            @supports[key][:prefixes] = nil
          end
        when :safelist
          val_warn(key, val) {
            @supports[key] = val.nil? ? true : val
          }
        when :statusmsg
          noval_warn(key, val) {
            @supports[key] = val.scan(/./)
          }
        when :std
          noval_warn(key, val) {
            @supports[key] = val.split(',')
          }
        else
          @supports[key] =  val.nil? ? true : val
        end
      }
      reparse.gsub!("(chantypes)",@supports[:chantypes])
      parse_isupport(reparse) unless reparse.empty?
    end

    # Returns the casemap of the server.
    #
    def casemap
      @supports[:casemapping] || 'rfc1459'
    end

    # Returns User or Channel depending on what _name_ can be
    # a name of
    #
    def user_or_channel?(name)
      if supports[:chantypes].include?(name[0].chr)
        return Channel
      else
        return User
      end
    end

    # Returns the actual User or Channel object matching _name_
    #
    def user_or_channel(name)
      if supports[:chantypes].include?(name[0].chr)
        return channel(name)
      else
        return user(name)
      end
    end

    # Checks if the receiver already has a channel with the given _name_
    #
    def has_channel?(name)
      @channel_names.index(name.to_s)
    end
    alias :has_chan? :has_channel?

    # Returns the channel with name _name_, if available
    #
    def get_channel(name)
      idx = @channel_names.index(name.to_s)
      @channels[idx] if idx
    end
    alias :get_chan :get_channel

    # Create a new Channel object and add it to the list of
    # <code>Channel</code>s on the receiver, unless the channel
    # was present already. In this case, the default action is
    # to raise an exception, unless _fails_ is set to false
    #
    # The Channel is automatically created with the appropriate casemap
    #
    def new_channel(name, topic=nil, users=[], fails=true)
      if !has_chan?(name)

        prefix = name[0].chr

        # Give a warning if the new Channel goes over some server limits.
        #
        # FIXME might need to raise an exception
        #
        warn "#{self} doesn't support channel prefix #{prefix}" unless @supports[:chantypes].include?(prefix)
        warn "#{self} doesn't support channel names this long (#{name.length} > #{@support[:channellen]}" unless name.length <= @supports[:channellen]

        # Next, we check if we hit the limit for channels of type +prefix+
        # if the server supports +chanlimit+
        #
        @supports[:chanlimit].keys.each { |k|
          next unless k.include?(prefix)
          count = 0
          @channel_names.each { |n|
            count += 1 if k.include?(n[0].chr)
          }
          raise IndexError, "Already joined #{count} channels with prefix #{k}" if count == @supports[:chanlimit][k]
        }

        # So far, everything is fine. Now create the actual Channel
        #
        chan = Channel.new(name, topic, users, self.casemap)

        # We wade through +prefix+ and +chanmodes+ to create appropriate
        # lists and flags for this channel

        @supports[:prefix][:modes].each { |mode|
          chan.create_mode(mode, ChannelUserMode)
        } if @supports[:prefix][:modes]

        @supports[:chanmodes].each { |k, val|
          if val
            case k
            when :typea
              val.each { |mode|
                chan.create_mode(mode, ChannelModeTypeA)
              }
            when :typeb
              val.each { |mode|
                chan.create_mode(mode, ChannelModeTypeB)
              }
            when :typec
              val.each { |mode|
                chan.create_mode(mode, ChannelModeTypeC)
              }
            when :typed
              val.each { |mode|
                chan.create_mode(mode, ChannelModeTypeD)
              }
            end
          end
        }

        @channels << chan
        @channel_names << name
        debug "Created channel #{chan.inspect}"
        debug "Managing channels #{@channel_names.join(', ')}"
        return chan
      end

      raise "Channel #{name} already exists on server #{self}" if fails
      return get_channel(name)
    end

    # Returns the Channel with the given _name_ on the server,
    # creating it if necessary. This is a short form for
    # new_channel(_str_, nil, [], +false+)
    #
    def channel(str)
      new_channel(str,nil,[],false)
    end

    # Remove Channel _name_ from the list of <code>Channel</code>s
    #
    def delete_channel(name)
      idx = has_channel?(name)
      raise "Tried to remove unmanaged channel #{name}" unless idx
      @channel_names.delete_at(idx)
      @channels.delete_at(idx)
    end

    # Checks if the receiver already has a user with the given _nick_
    #
    def has_user?(nick)
      @user_nicks.index(nick.to_s)
    end

    # Returns the user with nick _nick_, if available
    #
    def get_user(nick)
      idx = @user_nicks.index(nick.to_s)
      @users[idx] if idx
    end

    # Create a new User object and add it to the list of
    # <code>User</code>s on the receiver, unless the User
    # was present already. In this case, the default action is
    # to raise an exception, unless _fails_ is set to false
    #
    # The User is automatically created with the appropriate casemap
    #
    def new_user(str, fails=true)
      case str
      when User
        tmp = str
      else
        tmp = User.new(str, self.casemap)
      end
      if !has_user?(tmp.nick)
        warn "#{self} doesn't support nicknames this long (#{tmp.nick.length} > #{@support[:nicklen]}" unless tmp.nick.length <= @supports[:nicklen]
        @users << tmp
        @user_nicks << tmp.nick
        return @users.last
      end
      old = get_user(tmp.nick)
      if old.known?
        raise "User #{tmp.nick} has inconsistent Netmasks! #{self} knows #{old} but access was tried with #{tmp}" if old != tmp
        raise "User #{tmp} already exists on server #{self}" if fails
      else
        old.user = tmp.user
        old.host = tmp.host
      end
      return old
    end

    # Returns the User with the given Netmask on the server,
    # creating it if necessary. This is a short form for
    # new_user(_str_, +false+)
    #
    def user(str)
      new_user(str, false)
    end

    # Remove User _someuser_ from the list of <code>User</code>s.
    # _someuser_ must be specified with the full Netmask.
    #
    def delete_user(someuser)
      idx = has_user?(someuser.nick)
      raise "Tried to remove unmanaged user #{user}" unless idx
      have = self.user(someuser)
      raise "User #{someuser.nick} has inconsistent Netmasks! #{self} knows #{have} but access was tried with #{someuser}" if have != someuser && have.user != "*" && have.host != "*"
      @channels.each { |ch|
        delete_user_from_channel(have, ch)
      }
      @user_nicks.delete_at(idx)
      @users.delete_at(idx)
    end

    # Create a new Netmask object with the appropriate casemap
    #
    def new_netmask(str)
      if str.class <= Netmask 
        raise "Wrong casemap for Netmask #{str.inspect}" if str.casemap != self.casemap
        return str
      end
      Netmask.new(str, self.casemap)
    end

    # Finds all <code>User</code>s on server whose Netmask matches _mask_
    #
    def find_users(mask)
      nm = new_netmask(mask)
      @users.inject(UserList.new) {
        |list, user|
        if user.user == "*" or user.host == "*"
          list << user if user.nick =~ nm.nick.to_irc_regexp
        else
          list << user if user.matches?(nm)
        end
        list
      }
    end

    # Deletes User from Channel
    #
    def delete_user_from_channel(user, channel)
      channel.delete_user(user)
    end

  end
end

# TODO test cases

if __FILE__ == $0

include Irc

  # puts " -- irc_regexp tests"
  # ["*", "a?b", "a*b", "a\\*b", "a\\?b", "a?\\*b", "*a*\\**b?"].each { |s|
  #   puts " --"
  #   puts s.inspect
  #   puts s.to_irc_regexp.inspect
  #   puts "aUb".match(s.to_irc_regexp)[0] if "aUb" =~ s.to_irc_regexp
  # }

  # puts " -- Netmasks"
  # masks = []
  # masks << Netmask.new("start")
  # masks << masks[0].dup
  # masks << Netmask.new(masks[0])
  # puts masks.join("\n")
 
  # puts " -- Changing 1"
  # masks[1].nick = "me"
  # puts masks.join("\n")

  # puts " -- Changing 2"
  # masks[2].nick = "you"
  # puts masks.join("\n")

  # puts " -- Channel example"
  # ch = Channel.new("#prova")
  # p ch
  # puts " -- Methods"
  # puts ch.methods.sort.join("\n")
  # puts " -- Instance variables"
  # puts ch.instance_variables.join("\n")

end
