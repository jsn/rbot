#-- vim:sw=2:et
# General TODO list
# * do we want to handle a Channel list for each User telling which
#   Channels is the User on (of those the client is on too)?
#   We may want this so that when a User leaves all Channels and he hasn't
#   sent us privmsgs, we know we can remove him from the Server @users list
# * Maybe ChannelList and UserList should be HashesOf instead of ArrayOf?
#   See items marked as TODO Ho.
#   The framework to do this is now in place, thanks to the new [] method
#   for NetmaskList, which allows retrieval by Netmask or String
#++
# :title: IRC module
#
# Basic IRC stuff
#
# This module defines the fundamental building blocks for IRC
#
# Author:: Giuseppe Bilotta (giuseppe.bilotta@gmail.com)

require 'singleton'

class Object

  # We extend the Object class with a method that
  # checks if the receiver is nil or empty
  def nil_or_empty?
    return true unless self
    return true if self.respond_to? :empty? and self.empty?
    return false
  end

  # We alias the to_s method to __to_s__ to make
  # it accessible in all classes
  alias :__to_s__ :to_s 
end

# The Irc module is used to keep all IRC-related classes
# in the same namespace
#
module Irc


  # Due to its Scandinavian origins, IRC has strange case mappings, which
  # consider the characters <tt>{}|^</tt> as the uppercase
  # equivalents of # <tt>[]\~</tt>.
  #
  # This is however not the same on all IRC servers: some use standard ASCII
  # casemapping, other do not consider <tt>^</tt> as the uppercase of
  # <tt>~</tt>
  #
  class Casemap
    @@casemaps = {}

    # Create a new casemap with name _name_, uppercase characters _upper_ and
    # lowercase characters _lower_
    #
    def initialize(name, upper, lower)
      @key = name.to_sym
      raise "Casemap #{name.inspect} already exists!" if @@casemaps.has_key?(@key)
      @@casemaps[@key] = {
        :upper => upper,
        :lower => lower,
        :casemap => self
      }
    end

    # Returns the Casemap with the given name
    #
    def Casemap.get(name)
      @@casemaps[name.to_sym][:casemap]
    end

    # Retrieve the 'uppercase characters' of this Casemap
    #
    def upper
      @@casemaps[@key][:upper]
    end

    # Retrieve the 'lowercase characters' of this Casemap
    #
    def lower
      @@casemaps[@key][:lower]
    end

    # Return a Casemap based on the receiver
    #
    def to_irc_casemap
      self
    end

    # A Casemap is represented by its lower/upper mappings
    #
    def inspect
      self.__to_s__[0..-2] + " #{upper.inspect} ~(#{self})~ #{lower.inspect}>"
    end

    # As a String we return our name
    #
    def to_s
      @key.to_s
    end

    # Two Casemaps are equal if they have the same upper and lower ranges
    #
    def ==(arg)
      other = arg.to_irc_casemap
      return self.upper == other.upper && self.lower == other.lower
    end

    # Give a warning if _arg_ and self are not the same Casemap
    #
    def must_be(arg)
      other = arg.to_irc_casemap
      if self == other
        return true
      else
        warn "Casemap mismatch (#{self.inspect} != #{other.inspect})"
        return false
      end
    end

  end

  # The rfc1459 casemap
  #
  class RfcCasemap < Casemap
    include Singleton

    def initialize
      super('rfc1459', "\x41-\x5e", "\x61-\x7e")
    end

  end
  RfcCasemap.instance

  # The strict-rfc1459 Casemap
  #
  class StrictRfcCasemap < Casemap
    include Singleton

    def initialize
      super('strict-rfc1459', "\x41-\x5d", "\x61-\x7d")
    end

  end
  StrictRfcCasemap.instance

  # The ascii Casemap
  #
  class AsciiCasemap < Casemap
    include Singleton

    def initialize
      super('ascii', "\x41-\x5a", "\x61-\x7a")
    end

  end
  AsciiCasemap.instance


  # This module is included by all classes that are either bound to a server
  # or should have a casemap.
  #
  module ServerOrCasemap

    attr_reader :server

    # This method initializes the instance variables @server and @casemap
    # according to the values of the hash keys :server and :casemap in _opts_
    #
    def init_server_or_casemap(opts={})
      @server = opts.fetch(:server, nil)
      raise TypeError, "#{@server} is not a valid Irc::Server" if @server and not @server.kind_of?(Server)

      @casemap = opts.fetch(:casemap, nil)
      if @server
        if @casemap
          @server.casemap.must_be(@casemap)
          @casemap = nil
        end
      else
        @casemap = (@casemap || 'rfc1459').to_irc_casemap
      end
    end

    # This is an auxiliary method: it returns true if the receiver fits the
    # server and casemap specified in _opts_, false otherwise.
    #
    def fits_with_server_and_casemap?(opts={})
      srv = opts.fetch(:server, nil)
      cmap = opts.fetch(:casemap, nil)
      cmap = cmap.to_irc_casemap unless cmap.nil?

      if srv.nil?
        return true if cmap.nil? or cmap == casemap
      else
        return true if srv == @server and (cmap.nil? or cmap == casemap)
      end
      return false
    end

    # Returns the casemap of the receiver, by looking at the bound
    # @server (if possible) or at the @casemap otherwise
    #
    def casemap
      return @server.casemap if defined?(@server) and @server
      return @casemap
    end

    # Returns a hash with the current @server and @casemap as values of
    # :server and :casemap
    #
    def server_and_casemap
      h = {}
      h[:server] = @server if defined?(@server) and @server
      h[:casemap] = @casemap if defined?(@casemap) and @casemap
      h[:casemap] ||= @server.casemap if defined?(@server) and @server
      return h
    end

    # We allow up/downcasing with a different casemap
    #
    def irc_downcase(cmap=casemap)
      self.to_s.irc_downcase(cmap)
    end

    # Up/downcasing something that includes this module returns its
    # Up/downcased to_s form
    #
    def downcase
      self.irc_downcase
    end

    # We allow up/downcasing with a different casemap
    #
    def irc_upcase(cmap=casemap)
      self.to_s.irc_upcase(cmap)
    end

    # Up/downcasing something that includes this module returns its
    # Up/downcased to_s form
    #
    def upcase
      self.irc_upcase
    end

  end

end


# We start by extending the String class
# with some IRC-specific methods
#
class String

  # This method returns the Irc::Casemap whose name is the receiver
  #
  def to_irc_casemap
    Irc::Casemap.get(self) rescue raise TypeError, "Unkown Irc::Casemap #{self.inspect}"
  end

  # This method returns a string which is the downcased version of the
  # receiver, according to the given _casemap_
  #
  #
  def irc_downcase(casemap='rfc1459')
    cmap = casemap.to_irc_casemap
    self.tr(cmap.upper, cmap.lower)
  end

  # This is the same as the above, except that the string is altered in place
  #
  # See also the discussion about irc_downcase
  #
  def irc_downcase!(casemap='rfc1459')
    cmap = casemap.to_irc_casemap
    self.tr!(cmap.upper, cmap.lower)
  end

  # Upcasing functions are provided too
  #
  # See also the discussion about irc_downcase
  #
  def irc_upcase(casemap='rfc1459')
    cmap = casemap.to_irc_casemap
    self.tr(cmap.lower, cmap.upper)
  end

  # In-place upcasing
  #
  # See also the discussion about irc_downcase
  #
  def irc_upcase!(casemap='rfc1459')
    cmap = casemap.to_irc_casemap
    self.tr!(cmap.lower, cmap.upper)
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
    Regexp.new("^#{regmask}$")
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
    raise TypeError, "#{kl.inspect} must be a class name" unless kl.kind_of?(Class)
    super()
    @element_class = kl
    case ar
    when Array
      insert(0, *ar)
    else
      raise TypeError, "#{self.class} can only be initialized from an Array"
    end
  end

  def inspect
    self.__to_s__[0..-2].sub(/:[^:]+$/,"[#{@element_class}]\\0") + " #{super}>"
  end

  # Private method to check the validity of the elements passed to it
  # and optionally raise an error
  #
  # TODO should it accept nils as valid?
  #
  def internal_will_accept?(raising, *els)
    els.each { |el|
      unless el.kind_of?(@element_class)
        raise TypeError, "#{el.inspect} is not of class #{@element_class}" if raising
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
  #
  def validate
    raise TypeError unless valid?
  end

  # Overloaded from Array#<<, checks for appropriate class of argument
  #
  def <<(el)
    super(el) if internal_will_accept?(true, el)
  end

  # Overloaded from Array#&, checks for appropriate class of argument elements
  #
  def &(ar)
    r = super(ar)
    ArrayOf.new(@element_class, r) if internal_will_accept?(true, *r)
  end

  # Overloaded from Array#+, checks for appropriate class of argument elements
  #
  def +(ar)
    ArrayOf.new(@element_class, super(ar)) if internal_will_accept?(true, *ar)
  end

  # Overloaded from Array#-, so that an ArrayOf is returned. There is no need
  # to check the validity of the elements in the argument
  #
  def -(ar)
    ArrayOf.new(@element_class, super(ar)) # if internal_will_accept?(true, *ar)
  end

  # Overloaded from Array#|, checks for appropriate class of argument elements
  #
  def |(ar)
    ArrayOf.new(@element_class, super(ar)) if internal_will_accept?(true, *ar)
  end

  # Overloaded from Array#concat, checks for appropriate class of argument
  # elements
  #
  def concat(ar)
    super(ar) if internal_will_accept?(true, *ar)
  end

  # Overloaded from Array#insert, checks for appropriate class of argument
  # elements
  #
  def insert(idx, *ar)
    super(idx, *ar) if internal_will_accept?(true, *ar)
  end

  # Overloaded from Array#replace, checks for appropriate class of argument
  # elements
  #
  def replace(ar)
    super(ar) if (ar.kind_of?(ArrayOf) && ar.element_class <= @element_class) or internal_will_accept?(true, *ar)
  end

  # Overloaded from Array#push, checks for appropriate class of argument
  # elements
  #
  def push(*ar)
    super(*ar) if internal_will_accept?(true, *ar)
  end

  # Overloaded from Array#unshift, checks for appropriate class of argument(s)
  #
  def unshift(*els)
    els.each { |el|
      super(el) if internal_will_accept?(true, *els)
    }
  end

  # We introduce the 'downcase' method, which maps downcase() to all the Array
  # elements, properly failing when the elements don't have a downcase method
  #
  def downcase
    self.map { |el| el.downcase }
  end

  # Modifying methods which we don't handle yet are made private
  #
  private :[]=, :collect!, :map!, :fill, :flatten!

end


# We extend the Regexp class with an Irc module which will contain some
# Irc-specific regexps
#
class Regexp

  # We start with some general-purpose ones which will be used in the
  # Irc module too, but are useful regardless
  DIGITS = /\d+/
  HEX_DIGIT = /[0-9A-Fa-f]/
  HEX_DIGITS = /#{HEX_DIGIT}+/
  HEX_OCTET = /#{HEX_DIGIT}#{HEX_DIGIT}?/
  DEC_OCTET = /[01]?\d?\d|2[0-4]\d|25[0-5]/
  DEC_IP_ADDR = /#{DEC_OCTET}.#{DEC_OCTET}.#{DEC_OCTET}.#{DEC_OCTET}/
  HEX_IP_ADDR = /#{HEX_OCTET}.#{HEX_OCTET}.#{HEX_OCTET}.#{HEX_OCTET}/
  IP_ADDR = /#{DEC_IP_ADDR}|#{HEX_IP_ADDR}/

  # IPv6, from Resolv::IPv6, without the \A..\z anchors
  HEX_16BIT = /#{HEX_DIGIT}{1,4}/
  IP6_8Hex = /(?:#{HEX_16BIT}:){7}#{HEX_16BIT}/
  IP6_CompressedHex = /((?:#{HEX_16BIT}(?::#{HEX_16BIT})*)?)::((?:#{HEX_16BIT}(?::#{HEX_16BIT})*)?)/
  IP6_6Hex4Dec = /((?:#{HEX_16BIT}:){6,6})#{DEC_IP_ADDR}/
  IP6_CompressedHex4Dec = /((?:#{HEX_16BIT}(?::#{HEX_16BIT})*)?)::((?:#{HEX_16BIT}:)*)#{DEC_IP_ADDR}/
  IP6_ADDR = /(?:#{IP6_8Hex})|(?:#{IP6_CompressedHex})|(?:#{IP6_6Hex4Dec})|(?:#{IP6_CompressedHex4Dec})/

  # We start with some IRC related regular expressions, used to match
  # Irc::User nicks and users and Irc::Channel names
  #
  # For each of them we define two versions of the regular expression:
  # * a generic one, which should match for any server but may turn out to
  #   match more than a specific server would accept
  # * an RFC-compliant matcher
  #
  module Irc

    # Channel-name-matching regexps
    CHAN_FIRST = /[#&+]/
    CHAN_SAFE = /![A-Z0-9]{5}/
    CHAN_ANY = /[^\x00\x07\x0A\x0D ,:]/
    GEN_CHAN = /(?:#{CHAN_FIRST}|#{CHAN_SAFE})#{CHAN_ANY}+/
    RFC_CHAN = /#{CHAN_FIRST}#{CHAN_ANY}{1,49}|#{CHAN_SAFE}#{CHAN_ANY}{1,44}/

    # Nick-matching regexps
    SPECIAL_CHAR = /[\x5b-\x60\x7b-\x7d]/
    NICK_FIRST = /#{SPECIAL_CHAR}|[[:alpha:]]/
    NICK_ANY = /#{SPECIAL_CHAR}|[[:alnum:]]|-/
    GEN_NICK = /#{NICK_FIRST}#{NICK_ANY}+/
    RFC_NICK = /#{NICK_FIRST}#{NICK_ANY}{0,8}/

    USER_CHAR = /[^\x00\x0a\x0d @]/
    GEN_USER = /#{USER_CHAR}+/

    # Host-matching regexps
    HOSTNAME_COMPONENT = /[[:alnum:]](?:[[:alnum:]]|-)*[[:alnum:]]*/
    HOSTNAME = /#{HOSTNAME_COMPONENT}(?:\.#{HOSTNAME_COMPONENT})*/
    HOSTADDR = /#{IP_ADDR}|#{IP6_ADDR}/

    GEN_HOST = /#{HOSTNAME}|#{HOSTADDR}/

    # # FreeNode network replaces the host of affiliated users with
    # # 'virtual hosts' 
    # # FIXME we need the true syntax to match it properly ...
    # PDPC_HOST_PART = /[0-9A-Za-z.-]+/
    # PDPC_HOST = /#{PDPC_HOST_PART}(?:\/#{PDPC_HOST_PART})+/

    # # NOTE: the final optional and non-greedy dot is needed because some
    # # servers (e.g. FreeNode) send the hostname of the services as "services."
    # # which is not RFC compliant, but sadly done.
    # GEN_HOST_EXT = /#{PDPC_HOST}|#{GEN_HOST}\.??/ 

    # Sadly, different networks have different, RFC-breaking ways of cloaking
    # the actualy host address: see above for an example to handle FreeNode.
    # Another example would be Azzurra, wich also inserts a "=" in the
    # cloacked host. So let's just not care about this and go with the simplest
    # thing:
    GEN_HOST_EXT = /\S+/

    # User-matching Regexp
    GEN_USER_ID = /(#{GEN_NICK})(?:(?:!(#{GEN_USER}))?@(#{GEN_HOST_EXT}))?/

    # Things such has the BIP proxy send invalid nicks in a complete netmask,
    # so we want to match this, rather: this matches either a compliant nick
    # or a a string with a very generic nick, a very generic hostname after an
    # @ sign, and an optional user after a !
    BANG_AT = /#{GEN_NICK}|\S+?(?:!\S+?)?@\S+?/

    # # For Netmask, we want to allow wildcards * and ? in the nick
    # # (they are already allowed in the user and host part
    # GEN_NICK_MASK = /(?:#{NICK_FIRST}|[?*])?(?:#{NICK_ANY}|[?*])+/

    # # Netmask-matching Regexp
    # GEN_MASK = /(#{GEN_NICK_MASK})(?:(?:!(#{GEN_USER}))?@(#{GEN_HOST_EXT}))?/

  end

end


module Irc


  # A Netmask identifies each user by collecting its nick, username and
  # hostname in the form <tt>nick!user@host</tt>
  #
  # Netmasks can also contain glob patterns in any of their components; in
  # this form they are used to refer to more than a user or to a user
  # appearing under different forms.
  #
  # Example:
  # * <tt>*!*@*</tt> refers to everybody
  # * <tt>*!someuser@somehost</tt> refers to user +someuser+ on host +somehost+
  #   regardless of the nick used.
  #
  class Netmask

    # Netmasks have an associated casemap unless they are bound to a server
    #
    include ServerOrCasemap

    attr_reader :nick, :user, :host
    alias :ident :user

    # Create a new Netmask from string _str_, which must be in the form
    # _nick_!_user_@_host_
    #
    # It is possible to specify a server or a casemap in the optional Hash:
    # these are used to associate the Netmask with the given server and to set
    # its casemap: if a server is specified and a casemap is not, the server's
    # casemap is used. If both a server and a casemap are specified, the
    # casemap must match the server's casemap or an exception will be raised.
    #
    # Empty +nick+, +user+ or +host+ are converted to the generic glob pattern
    #
    def initialize(str="", opts={})
      # First of all, check for server/casemap option
      #
      init_server_or_casemap(opts)

      # Now we can see if the given string _str_ is an actual Netmask
      if str.respond_to?(:to_str)
        case str.to_str
          # We match a pretty generic string, to work around non-compliant
          # servers
        when /^(?:(\S+?)(?:(?:!(\S+?))?@(\S+))?)?$/
          # We do assignment using our internal methods
          self.nick = $1
          self.user = $2
          self.host = $3
        else
          raise ArgumentError, "#{str.to_str.inspect} does not represent a valid #{self.class}"
        end
      else
        raise TypeError, "#{str} cannot be converted to a #{self.class}"
      end
    end

    # A Netmask is easily converted to a String for the usual representation.
    # We skip the user or host parts if they are "*", unless we've been asked
    # for the full form
    #
    def to_s
      ret = nick.dup
      ret << "!" << user unless user == "*"
      ret << "@" << host unless host == "*"
      return ret
    end

    def fullform
      "#{nick}!#{user}@#{host}"
    end

    alias :to_str :fullform

    # This method downcases the fullform of the netmask. While this may not be
    # significantly different from the #downcase() method provided by the
    # ServerOrCasemap mixin, it's significantly different for Netmask
    # subclasses such as User whose simple downcasing uses the nick only.
    #
    def full_irc_downcase(cmap=casemap)
      self.fullform.irc_downcase(cmap)
    end

    # full_downcase() will return the fullform downcased according to the
    # User's own casemap
    #
    def full_downcase
      self.full_irc_downcase
    end

    # This method returns a new Netmask which is the fully downcased version
    # of the receiver
    def downcased
      return self.full_downcase.to_irc_netmask(server_and_casemap)
    end

    # Converts the receiver into a Netmask with the given (optional)
    # server/casemap association. We return self unless a conversion
    # is needed (different casemap/server)
    #
    # Subclasses of Netmask will return a new Netmask, using full_downcase
    #
    def to_irc_netmask(opts={})
      if self.class == Netmask and not opts[:force]
        return self if fits_with_server_and_casemap?(opts)
      end
      return self.full_downcase.to_irc_netmask(server_and_casemap.merge(opts))
    end

    # Converts the receiver into a User with the given (optional)
    # server/casemap association. We return self unless a conversion
    # is needed (different casemap/server)
    #
    def to_irc_user(opts={})
      self.fullform.to_irc_user(server_and_casemap.merge(opts))
    end

    # Inspection of a Netmask reveals the server it's bound to (if there is
    # one), its casemap and the nick, user and host part
    #
    def inspect
      str = self.__to_s__[0..-2]
      str << " @server=#{@server}" if defined?(@server) and @server
      str << " @nick=#{@nick.inspect} @user=#{@user.inspect}"
      str << " @host=#{@host.inspect} casemap=#{casemap.inspect}"
      str << ">"
    end

    # Equality: two Netmasks are equal if they downcase to the same thing
    #
    # TODO we may want it to try other.to_irc_netmask
    #
    def ==(other)
      return false unless other.kind_of?(self.class)
      self.downcase == other.downcase
    end

    # This method changes the nick of the Netmask, defaulting to the generic
    # glob pattern if the result is the null string.
    #
    def nick=(newnick)
      @nick = newnick.to_s
      @nick = "*" if @nick.empty?
    end

    # This method changes the user of the Netmask, defaulting to the generic
    # glob pattern if the result is the null string.
    #
    def user=(newuser)
      @user = newuser.to_s
      @user = "*" if @user.empty?
    end
    alias :ident= :user=

    # This method changes the hostname of the Netmask, defaulting to the generic
    # glob pattern if the result is the null string.
    #
    def host=(newhost)
      @host = newhost.to_s
      @host = "*" if @host.empty?
    end

    # We can replace everything at once with data from another Netmask
    #
    def replace(other)
      case other
      when Netmask
        nick = other.nick
        user = other.user
        host = other.host
        @server = other.server
        @casemap = other.casemap unless @server
      else
        replace(other.to_irc_netmask(server_and_casemap))
      end
    end

    # This method checks if a Netmask is definite or not, by seeing if
    # any of its components are defined by globs
    #
    def has_irc_glob?
      return @nick.has_irc_glob? || @user.has_irc_glob? || @host.has_irc_glob?
    end

    def generalize
      u = user.dup
      unless u.has_irc_glob?
        u.sub!(/^[in]=/, '=') or u.sub!(/^\W(\w+)/, '\1')
        u = '*' + u
      end

      h = host.dup
      unless h.has_irc_glob?
        if h.include? '/'
          h.sub!(/x-\w+$/, 'x-*')
        else
          h.match(/^[^\.]+\.[^\.]+$/) or
          h.sub!(/azzurra[=-][0-9a-f]+/i, '*') or # hello, azzurra, you suck!
          h.sub!(/^(\d+\.\d+\.\d+\.)\d+$/, '\1*') or
          h.sub!(/^[^\.]+\./, '*.')
        end
      end
      return Netmask.new("*!#{u}@#{h}", server_and_casemap)
    end

    # This method is used to match the current Netmask against another one
    #
    # The method returns true if each component of the receiver matches the
    # corresponding component of the argument. By _matching_ here we mean
    # that any netmask described by the receiver is also described by the
    # argument.
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
      cmp = arg.to_irc_netmask(:casemap => casemap)
      debug "Matching #{self.fullform} against #{arg.inspect} (#{cmp.fullform})"
      [:nick, :user, :host].each { |component|
        us = self.send(component).irc_downcase(casemap)
        them = cmp.send(component).irc_downcase(casemap)
        if us.has_irc_glob? && them.has_irc_glob?
          next if us == them
          warn NotImplementedError
          return false
        end
        return false if us.has_irc_glob? && !them.has_irc_glob?
        return false unless us =~ them.to_irc_regexp
      }
      return true
    end

    # Case equality. Checks if arg matches self
    #
    def ===(arg)
      arg.to_irc_netmask(:casemap => casemap).matches?(self)
    end

    # Sorting is done via the fullform
    #
    def <=>(arg)
      case arg
      when Netmask
        self.fullform.irc_downcase(casemap) <=> arg.fullform.irc_downcase(casemap)
      else
        self.downcase <=> arg.downcase
      end
    end

  end


  # A NetmaskList is an ArrayOf <code>Netmask</code>s
  #
  class NetmaskList < ArrayOf

    # Create a new NetmaskList, optionally filling it with the elements from
    # the Array argument fed to it.
    #
    def initialize(ar=[])
      super(Netmask, ar)
    end

    # We enhance the [] method by allowing it to pick an element that matches
    # a given Netmask, a String or a Regexp
    # TODO take into consideration the opportunity to use select() instead of
    # find(), and/or a way to let the user choose which one to take (second
    # argument?)
    #
    def [](*args)
      if args.length == 1
        case args[0]
        when Netmask
          self.find { |mask|
            mask.matches?(args[0])
          }
        when String
          self.find { |mask|
            mask.matches?(args[0].to_irc_netmask(:casemap => mask.casemap))
          }
        when Regexp
          self.find { |mask|
            mask.fullform =~ args[0]
          }
        else
          super(*args)
        end
      else
        super(*args)
      end
    end

  end

end


class String

  # We keep extending String, this time adding a method that converts a
  # String into an Irc::Netmask object
  #
  def to_irc_netmask(opts={})
    Irc::Netmask.new(self, opts)
  end

end


module Irc


  # An IRC User is identified by his/her Netmask (which must not have globs).
  # In fact, User is just a subclass of Netmask.
  #
  # Ideally, the user and host information of an IRC User should never
  # change, and it shouldn't contain glob patterns. However, IRC is somewhat
  # idiosincratic and it may be possible to know the nick of a User much before
  # its user and host are known. Moreover, some networks (namely Freenode) may
  # change the hostname of a User when (s)he identifies with Nickserv.
  #
  # As a consequence, we must allow changes to a User host and user attributes.
  # We impose a restriction, though: they may not contain glob patterns, except
  # for the special case of an unknown user/host which is represented by a *.
  #
  # It is possible to create a totally unknown User (e.g. for initializations)
  # by setting the nick to * too.
  #
  # TODO list:
  # * see if it's worth to add the other USER data
  # * see if it's worth to add NICKSERV status
  #
  class User < Netmask
    alias :to_s :nick

    attr_accessor :real_name

    # Create a new IRC User from a given Netmask (or anything that can be converted
    # into a Netmask) provided that the given Netmask does not have globs.
    #
    def initialize(str="", opts={})
      super
      raise ArgumentError, "#{str.inspect} must not have globs (unescaped * or ?)" if nick.has_irc_glob? && nick != "*"
      raise ArgumentError, "#{str.inspect} must not have globs (unescaped * or ?)" if user.has_irc_glob? && user != "*"
      raise ArgumentError, "#{str.inspect} must not have globs (unescaped * or ?)" if host.has_irc_glob? && host != "*"
      @away = false
      @real_name = String.new
    end

    # The nick of a User may be changed freely, but it must not contain glob patterns.
    #
    def nick=(newnick)
      raise "Can't change the nick to #{newnick}" if defined?(@nick) and newnick.has_irc_glob?
      super
    end

    # We have to allow changing the user of an Irc User due to some networks
    # (e.g. Freenode) changing hostmasks on the fly. We still check if the new
    # user data has glob patterns though.
    #
    def user=(newuser)
      raise "Can't change the username to #{newuser}" if defined?(@user) and newuser.has_irc_glob?
      super
    end

    # We have to allow changing the host of an Irc User due to some networks
    # (e.g. Freenode) changing hostmasks on the fly. We still check if the new
    # host data has glob patterns though.
    #
    def host=(newhost)
      raise "Can't change the hostname to #{newhost}" if defined?(@host) and newhost.has_irc_glob?
      super
    end

    # Checks if a User is well-known or not by looking at the hostname and user
    #
    def known?
      return nick != "*" && user != "*" && host != "*"
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

    # Since to_irc_user runs the same checks on server and channel as
    # to_irc_netmask, we just try that and return self if it works.
    #
    # Subclasses of User will return self if possible.
    #
    def to_irc_user(opts={})
      return self if fits_with_server_and_casemap?(opts)
      return self.full_downcase.to_irc_user(opts)
    end

    # We can replace everything at once with data from another User
    #
    def replace(other)
      case other
      when User
        self.nick = other.nick
        self.user = other.user
        self.host = other.host
        @server = other.server
        @casemap = other.casemap unless @server
        @away = other.away?
      else
        self.replace(other.to_irc_user(server_and_casemap))
      end
    end

    def modes_on(channel)
      case channel
      when Channel
        channel.modes_of(self)
      else
        return @server.channel(channel).modes_of(self) if @server
        raise "Can't resolve channel #{channel}"
      end
    end

    def is_op?(channel)
      case channel
      when Channel
        channel.has_op?(self)
      else
        return @server.channel(channel).has_op?(self) if @server
        raise "Can't resolve channel #{channel}"
      end
    end

    def is_voice?(channel)
      case channel
      when Channel
        channel.has_voice?(self)
      else
        return @server.channel(channel).has_voice?(self) if @server
        raise "Can't resolve channel #{channel}"
      end
    end
  end


  # A UserList is an ArrayOf <code>User</code>s
  # We derive it from NetmaskList, which allows us to inherit any special
  # NetmaskList method
  #
  class UserList < NetmaskList

    # Create a new UserList, optionally filling it with the elements from
    # the Array argument fed to it.
    #
    def initialize(ar=[])
      super(ar)
      @element_class = User
    end

    # Convenience method: convert the UserList to a list of nicks. The indices
    # are preserved
    #
    def nicks
      self.map { |user| user.nick }
    end

  end

end

class String

  # We keep extending String, this time adding a method that converts a
  # String into an Irc::User object
  #
  def to_irc_user(opts={})
    Irc::User.new(self, opts)
  end

end

module Irc

  # An IRC Channel is identified by its name, and it has a set of properties:
  # * a Channel::Topic
  # * a UserList
  # * a set of Channel::Modes
  #
  # The Channel::Topic and Channel::Mode classes are defined within the
  # Channel namespace because they only make sense there
  #
  class Channel


    # Mode on a Channel
    #
    class Mode
      attr_reader :channel
      def initialize(ch)
        @channel = ch
      end

    end

    # Hash of modes. Subclass of Hash that defines any? and all?
    # to check if boolean modes (Type D) are set
    class ModeHash < Hash
      def any?(*ar)
        !!ar.find { |m| s = m.to_sym ; self[s] && self[s].set? }
      end
      def all?(*ar)
        !ar.find { |m| s = m.to_sym ; !(self[s] && self[s].set?) }
      end
    end

    # Channel modes of type A manipulate lists
    #
    # Example: b (banlist)
    #
    class ModeTypeA < Mode
      attr_reader :list
      def initialize(ch)
        super
        @list = NetmaskList.new
      end

      def set(val)
        nm = @channel.server.new_netmask(val)
        @list << nm unless @list.include?(nm)
      end

      def reset(val)
        nm = @channel.server.new_netmask(val)
        @list.delete(nm)
      end

    end


    # Channel modes of type B need an argument
    #
    # Example: k (key)
    #
    class ModeTypeB < Mode
      def initialize(ch)
        super
        @arg = nil
      end

      def status
        @arg
      end
      alias :value :status

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
    class UserMode < ModeTypeB
      attr_reader :list
      alias :users :list
      def initialize(ch)
        super
        @list = UserList.new
      end

      def set(val)
        u = @channel.server.user(val)
        @list << u unless @list.include?(u)
      end

      def reset(val)
        u = @channel.server.user(val)
        @list.delete(u)
      end

    end


    # Channel modes of type C need an argument when set,
    # but not when they get reset
    #
    # Example: l (limit)
    #
    class ModeTypeC < Mode
      def initialize(ch)
        super
        @arg = nil
      end

      def status
        @arg
      end
      alias :value :status

      def set(val)
        @arg = val
      end

      def reset
        @arg = nil
      end

    end


    # Channel modes of type D are basically booleans
    #
    # Example: m (moderate)
    #
    class ModeTypeD < Mode
      def initialize(ch)
        super
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


    # A Topic represents the topic of a channel. It consists of
    # the topic itself, who set it and when
    #
    class Topic
      attr_accessor :text, :set_by, :set_on
      alias :to_s :text

      # Create a new Topic setting the text, the creator and
      # the creation time
      #
      def initialize(text="", set_by="", set_on=Time.new)
        @text = text
        @set_by = set_by.to_irc_netmask
        @set_on = set_on
      end

      # Replace a Topic with another one
      #
      def replace(topic)
        raise TypeError, "#{topic.inspect} is not of class #{self.class}" unless topic.kind_of?(self.class)
        @text = topic.text.dup
        @set_by = topic.set_by.dup
        @set_on = topic.set_on.dup
      end

      # Returns self
      #
      def to_irc_channel_topic
        self
      end

    end

  end

end


class String

  # Returns an Irc::Channel::Topic with self as text
  #
  def to_irc_channel_topic
    Irc::Channel::Topic.new(self)
  end

end


module Irc


  # Here we start with the actual Channel class
  #
  class Channel

    include ServerOrCasemap
    attr_reader :name, :topic, :mode, :users
    alias :to_s :name

    def inspect
      str = self.__to_s__[0..-2]
      str << " on server #{server}" if server
      str << " @name=#{@name.inspect} @topic=#{@topic.text.inspect}"
      str << " @users=[#{user_nicks.sort.join(', ')}]"
      str << ">"
    end

    # Returns self
    #
    def to_irc_channel
      self
    end

    # TODO Ho
    def user_nicks
      @users.map { |u| u.downcase }
    end

    # Checks if the receiver already has a user with the given _nick_
    #
    def has_user?(nick)
      @users.index(nick.to_irc_user(server_and_casemap))
    end

    # Returns the user with nick _nick_, if available
    #
    def get_user(nick)
      idx = has_user?(nick)
      @users[idx] if idx
    end

    # Adds a user to the channel
    #
    def add_user(user, opts={})
      silent = opts.fetch(:silent, false) 
      if has_user?(user)
        warn "Trying to add user #{user} to channel #{self} again" unless silent
      else
        @users << user.to_irc_user(server_and_casemap)
      end
    end

    # Creates a new channel with the given name, optionally setting the topic
    # and an initial users list.
    #
    # No additional info is created here, because the channel flags and userlists
    # allowed depend on the server.
    #
    def initialize(name, topic=nil, users=[], opts={})
      raise ArgumentError, "Channel name cannot be empty" if name.to_s.empty?
      warn "Unknown channel prefix #{name[0].chr}" if name !~ /^[&#+!]/
      raise ArgumentError, "Invalid character in #{name.inspect}" if name =~ /[ \x07,]/

      init_server_or_casemap(opts)

      @name = name

      @topic = topic ? topic.to_irc_channel_topic : Channel::Topic.new

      @users = UserList.new

      users.each { |u|
        add_user(u)
      }

      # Flags
      @mode = ModeHash.new
    end

    # Removes a user from the channel
    #
    def delete_user(user)
      @mode.each { |sym, mode|
        mode.reset(user) if mode.kind_of?(UserMode)
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
      name[0] == 0x26
    end

    # A channel is modeless if it has the '+' prefix
    #
    def modeless?
      name[0] == 0x2b
    end

    # A channel is safe if it has the '!' prefix
    #
    def safe?
      name[0] == 0x21
    end

    # A channel is normal if it has the '#' prefix
    #
    def normal?
      name[0] == 0x23
    end

    # Create a new mode
    #
    def create_mode(sym, kl)
      @mode[sym.to_sym] = kl.new(self)
    end

    def modes_of(user)
      l = []
      @mode.map { |s, m|
        l << s if (m.class <= UserMode and m.list[user])
      }
      l
    end

    def has_op?(user)
      @mode.has_key?(:o) and @mode[:o].list[user]
    end

    def has_voice?(user)
      @mode.has_key?(:v) and @mode[:v].list[user]
    end
  end


  # A ChannelList is an ArrayOf <code>Channel</code>s
  #
  class ChannelList < ArrayOf

    # Create a new ChannelList, optionally filling it with the elements from
    # the Array argument fed to it.
    #
    def initialize(ar=[])
      super(Channel, ar)
    end

    # Convenience method: convert the ChannelList to a list of channel names.
    # The indices are preserved
    #
    def names
      self.map { |chan| chan.name }
    end

  end

end


class String

  # We keep extending String, this time adding a method that converts a
  # String into an Irc::Channel object
  #
  def to_irc_channel(opts={})
    Irc::Channel.new(self, opts)
  end

end


module Irc


  # An IRC Server represents the Server the client is connected to.
  #
  class Server

    attr_reader :hostname, :version, :usermodes, :chanmodes
    alias :to_s :hostname
    attr_reader :supports, :capabilities

    attr_reader :channels, :users

    # TODO Ho
    def channel_names
      @channels.map { |ch| ch.downcase }
    end

    # TODO Ho
    def user_nicks
      @users.map { |u| u.downcase }
    end

    def inspect
      chans, users = [@channels, @users].map {|d|
        d.sort { |a, b|
          a.downcase <=> b.downcase
        }.map { |x|
          x.inspect
        }
      }

      str = self.__to_s__[0..-2]
      str << " @hostname=#{hostname}"
      str << " @channels=#{chans}"
      str << " @users=#{users}"
      str << ">"
    end

    # Create a new Server, with all instance variables reset to nil (for
    # scalar variables), empty channel and user lists and @supports
    # initialized to the default values for all known supported features.
    #
    def initialize
      @hostname = @version = @usermodes = @chanmodes = nil

      @channels = ChannelList.new

      @users = UserList.new

      reset_capabilities
    end

    # Resets the server capabilities
    #
    def reset_capabilities
      @supports = {
        :casemapping => 'rfc1459'.to_irc_casemap,
        :chanlimit => {},
        :chanmodes => {
          :typea => nil, # Type A: address lists
          :typeb => nil, # Type B: needs a parameter
          :typec => nil, # Type C: needs a parameter when set
          :typed => nil  # Type D: must not have a parameter
        },
        :channellen => 50,
        :chantypes => "#&!+",
        :excepts => nil,
        :idchan => {},
        :invex => nil,
        :kicklen => nil,
        :maxlist => {},
        :modes => 3,
        :network => nil,
        :nicklen => 9,
        :prefix => {
          :modes => [:o, :v],
          :prefixes => [:"@", :+]
        },
        :safelist => nil,
        :statusmsg => nil,
        :std => nil,
        :targmax => {},
        :topiclen => nil
      }
      @capabilities = {}
    end

    # Convert a mode (o, v, h, ...) to the corresponding
    # prefix (@, +, %, ...). See also mode_for_prefix
    def prefix_for_mode(mode)
      return @supports[:prefix][:prefixes][
        @supports[:prefix][:modes].index(mode.to_sym)
      ]
    end

    # Convert a prefix (@, +, %, ...) to the corresponding
    # mode (o, v, h, ...). See also prefix_for_mode
    def mode_for_prefix(pfx)
      return @supports[:prefix][:modes][
        @supports[:prefix][:prefixes].index(pfx.to_sym)
      ]
    end

    # Resets the Channel and User list
    #
    def reset_lists
      @users.reverse_each { |u|
        delete_user(u)
      }
      @channels.reverse_each { |u|
        delete_channel(u)
      }
    end

    # Clears the server
    #
    def clear
      reset_lists
      reset_capabilities
      @hostname = @version = @usermodes = @chanmodes = nil
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
      debug "Parsing ISUPPORT #{line.inspect}"
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
        when :casemapping
          noval_warn(key, val) {
            @supports[key] = val.to_irc_casemap
          }
        when :chanlimit, :idchan, :maxlist, :targmax
          noval_warn(key, val) {
            groups = val.split(',')
            groups.each { |g|
              k, v = g.split(':')
              @supports[key][k] = v.to_i || 0
              if @supports[key][k] == 0
                warn "Deleting #{key} limit of 0 for #{k}"
                @supports[key].delete(k)
              end
            }
          }
        when :chanmodes
          noval_warn(key, val) {
            groups = val.split(',')
            @supports[key][:typea] = groups[0].scan(/./).map { |x| x.to_sym}
            @supports[key][:typeb] = groups[1].scan(/./).map { |x| x.to_sym}
            @supports[key][:typec] = groups[2].scan(/./).map { |x| x.to_sym}
            @supports[key][:typed] = groups[3].scan(/./).map { |x| x.to_sym}
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
        when :maxchannels
          noval_warn(key, val) {
            reparse += "CHANLIMIT=(chantypes):#{val} "
          }
        when :maxtargets
          noval_warn(key, val) {
            @supports[:targmax]['PRIVMSG'] = val.to_i
            @supports[:targmax]['NOTICE'] = val.to_i
          }
        when :network
          noval_warn(key, val) {
            @supports[key] = val
          }
        when :nicklen
          noval_warn(key, val) {
            @supports[key] = val.to_i
          }
        when :prefix
          if val
            val.scan(/\((.*)\)(.*)/) { |m, p|
              @supports[key][:modes] = m.scan(/./).map { |x| x.to_sym}
              @supports[key][:prefixes] = p.scan(/./).map { |x| x.to_sym}
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
      @supports[:casemapping]
    end

    # Returns User or Channel depending on what _name_ can be
    # a name of
    #
    def user_or_channel?(name)
      if supports[:chantypes].include?(name[0])
        return Channel
      else
        return User
      end
    end

    # Returns the actual User or Channel object matching _name_
    #
    def user_or_channel(name)
      if supports[:chantypes].include?(name[0])
        return channel(name)
      else
        return user(name)
      end
    end

    # Checks if the receiver already has a channel with the given _name_
    #
    def has_channel?(name)
      return false if name.nil_or_empty?
      channel_names.index(name.irc_downcase(casemap))
    end
    alias :has_chan? :has_channel?

    # Returns the channel with name _name_, if available
    #
    def get_channel(name)
      return nil if name.nil_or_empty?
      idx = has_channel?(name)
      channels[idx] if idx
    end
    alias :get_chan :get_channel

    # Create a new Channel object bound to the receiver and add it to the
    # list of <code>Channel</code>s on the receiver, unless the channel was
    # present already. In this case, the default action is to raise an
    # exception, unless _fails_ is set to false.  An exception can also be
    # raised if _str_ is nil or empty, again only if _fails_ is set to true;
    # otherwise, the method just returns nil
    #
    def new_channel(name, topic=nil, users=[], fails=true)
      if name.nil_or_empty?
        raise "Tried to look for empty or nil channel name #{name.inspect}" if fails
        return nil
      end
      ex = get_chan(name)
      if ex
        raise "Channel #{name} already exists on server #{self}" if fails
        return ex
      else

        prefix = name[0].chr

        # Give a warning if the new Channel goes over some server limits.
        #
        # FIXME might need to raise an exception
        #
        warn "#{self} doesn't support channel prefix #{prefix}" unless @supports[:chantypes].include?(prefix)
        warn "#{self} doesn't support channel names this long (#{name.length} > #{@supports[:channellen]})" unless name.length <= @supports[:channellen]

        # Next, we check if we hit the limit for channels of type +prefix+
        # if the server supports +chanlimit+
        #
        @supports[:chanlimit].keys.each { |k|
          next unless k.include?(prefix)
          count = 0
          channel_names.each { |n|
            count += 1 if k.include?(n[0])
          }
          # raise IndexError, "Already joined #{count} channels with prefix #{k}" if count == @supports[:chanlimit][k]
          warn "Already joined #{count}/#{@supports[:chanlimit][k]} channels with prefix #{k}, we may be going over server limits" if count >= @supports[:chanlimit][k]
        }

        # So far, everything is fine. Now create the actual Channel
        #
        chan = Channel.new(name, topic, users, :server => self)

        # We wade through +prefix+ and +chanmodes+ to create appropriate
        # lists and flags for this channel

        @supports[:prefix][:modes].each { |mode|
          chan.create_mode(mode, Channel::UserMode)
        } if @supports[:prefix][:modes]

        @supports[:chanmodes].each { |k, val|
          if val
            case k
            when :typea
              val.each { |mode|
                chan.create_mode(mode, Channel::ModeTypeA)
              }
            when :typeb
              val.each { |mode|
                chan.create_mode(mode, Channel::ModeTypeB)
              }
            when :typec
              val.each { |mode|
                chan.create_mode(mode, Channel::ModeTypeC)
              }
            when :typed
              val.each { |mode|
                chan.create_mode(mode, Channel::ModeTypeD)
              }
            end
          end
        }

        @channels << chan
        # debug "Created channel #{chan.inspect}"
        return chan
      end
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
      @channels.delete_at(idx)
    end

    # Checks if the receiver already has a user with the given _nick_
    #
    def has_user?(nick)
      return false if nick.nil_or_empty?
      user_nicks.index(nick.irc_downcase(casemap))
    end

    # Returns the user with nick _nick_, if available
    #
    def get_user(nick)
      idx = has_user?(nick)
      @users[idx] if idx
    end

    # Create a new User object bound to the receiver and add it to the list
    # of <code>User</code>s on the receiver, unless the User was present
    # already. In this case, the default action is to raise an exception,
    # unless _fails_ is set to false. An exception can also be raised
    # if _str_ is nil or empty, again only if _fails_ is set to true;
    # otherwise, the method just returns nil
    #
    def new_user(str, fails=true)
      if str.nil_or_empty?
        raise "Tried to look for empty or nil user name #{str.inspect}" if fails
        return nil
      end
      tmp = str.to_irc_user(:server => self)
      old = get_user(tmp.nick)
      # debug "Tmp: #{tmp.inspect}"
      # debug "Old: #{old.inspect}"
      if old
        # debug "User already existed as #{old.inspect}"
        if tmp.known?
          if old.known?
            # debug "Both were known"
            # Do not raise an error: things like Freenode change the hostname after identification
            warning "User #{tmp.nick} has inconsistent Netmasks! #{self} knows #{old.inspect} but access was tried with #{tmp.inspect}" if old != tmp
            raise "User #{tmp} already exists on server #{self}" if fails
          end
          if old.fullform.downcase != tmp.fullform.downcase
            old.replace(tmp)
            # debug "Known user now #{old.inspect}"
          end
        end
        return old
      else
        warn "#{self} doesn't support nicknames this long (#{tmp.nick.length} > #{@supports[:nicklen]})" unless tmp.nick.length <= @supports[:nicklen]
        @users << tmp
        return @users.last
      end
    end

    # Returns the User with the given Netmask on the server,
    # creating it if necessary. This is a short form for
    # new_user(_str_, +false+)
    #
    def user(str)
      new_user(str, false)
    end

    # Deletes User _user_ from Channel _channel_
    #
    def delete_user_from_channel(user, channel)
      channel.delete_user(user)
    end

    # Remove User _someuser_ from the list of <code>User</code>s.
    # _someuser_ must be specified with the full Netmask.
    #
    def delete_user(someuser)
      idx = has_user?(someuser)
      raise "Tried to remove unmanaged user #{user}" unless idx
      have = self.user(someuser)
      @channels.each { |ch|
        delete_user_from_channel(have, ch)
      }
      @users.delete_at(idx)
    end

    # Create a new Netmask object with the appropriate casemap
    #
    def new_netmask(str)
      str.to_irc_netmask(:server => self)
    end

    # Finds all <code>User</code>s on server whose Netmask matches _mask_
    #
    def find_users(mask)
      nm = new_netmask(mask)
      @users.inject(UserList.new) {
        |list, user|
        if user.user == "*" or user.host == "*"
          list << user if user.nick.irc_downcase(casemap) =~ nm.nick.irc_downcase(casemap).to_irc_regexp
        else
          list << user if user.matches?(nm)
        end
        list
      }
    end

  end

end

