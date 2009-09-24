#-- vim:sw=2:et
#++
#
# :title: Standard classes extensions
#
# Author:: Giuseppe "Oblomov" Bilotta <giuseppe.bilotta@gmail.com>
#
# This file collects extensions to standard Ruby classes and to some core rbot
# classes to be used by the various plugins
#
# Please note that global symbols have to be prefixed by :: because this plugin
# will be read into an anonymous module

# Extensions to the Module class
#
class ::Module

  # Many plugins define Struct objects to hold their data. On rescans, lots of
  # warnings are echoed because of the redefinitions. Using this method solves
  # the problem, by checking if the Struct already exists, and if it has the
  # same attributes
  #
  def define_structure(name, *members)
    sym = name.to_sym
    if Struct.const_defined?(sym)
      kl = Struct.const_get(sym)
      if kl.new.members.map { |member| member.intern } == members.map
        debug "Struct #{sym} previously defined, skipping"
        const_set(sym, kl)
        return
      end
    end
    debug "Defining struct #{sym} with members #{members.inspect}"
    const_set(sym, Struct.new(name.to_s, *members))
  end
end


# DottedIndex mixin: extend a Hash or Array class with this module
# to achieve [] and []= methods that automatically split indices
# at dots (indices are automatically converted to symbols, too)
#
# You have to define the single_retrieve(_key_) and
# single_assign(_key_,_value_) methods (usually aliased at the
# original :[] and :[]= methods)
#
module ::DottedIndex
  def rbot_index_split(*ar)
    keys = ([] << ar).flatten
    keys.map! { |k|
      k.to_s.split('.').map { |kk| kk.to_sym rescue nil }.compact
    }.flatten
  end

  def [](*ar)
    keys = self.rbot_index_split(ar)
    return self.single_retrieve(keys.first) if keys.length == 1
    h = self
    while keys.length > 1
      k = keys.shift
      h[k] ||= self.class.new
      h = h[k]
    end
    h[keys.last]
  end

  def []=(*arr)
    val = arr.last
    ar = arr[0..-2]
    keys = self.rbot_index_split(ar)
    return self.single_assign(keys.first, val) if keys.length == 1
    h = self
    while keys.length > 1
      k = keys.shift
      h[k] ||= self.class.new
      h = h[k]
    end
    h[keys.last] = val
  end
end


# Extensions to the Array class
#
class ::Array

  # This method returns a random element from the array, or nil if the array is
  # empty
  #
  def pick_one
    return nil if self.empty?
    self[rand(self.length)]
  end

  # This method returns a given element from the array, deleting it from the
  # array itself. The method returns nil if the element couldn't be found.
  #
  # If nil is specified, a random element is returned and deleted.
  #
  def delete_one(val=nil)
    return nil if self.empty?
    if val.nil?
      index = rand(self.length)
    else
      index = self.index(val)
      return nil unless index
    end
    self.delete_at(index)
  end

  # shuffle and shuffle! are defined in Ruby >= 1.8.7

  # This method returns a new array with the same items as
  # the receiver, but shuffled
  unless method_defined? :shuffle
    def shuffle
      sort_by { rand }
    end
  end

  # This method shuffles the items in the array
  unless method_defined? :shuffle!
    def shuffle!
      replace shuffle
    end
  end
end

module ::Enumerable
  # This method is an advanced version of #join
  # allowing fine control of separators:
  #
  #   [1,2,3].conjoin(', ', ' and ')
  #   => "1, 2 and 3
  #
  #   [1,2,3,4].conjoin{ |i, a, b| i % 2 == 0 ? '.' : '-' }
  #   => "1.2-3.4"
  #
  # Code lifted from the ruby facets project:
  # <http://facets.rubyforge.org>
  # git-rev: c8b7395255b977d3c7de268ff563e3c5bc7f1441
  # file: lib/core/facets/array/conjoin.rb
  def conjoin(*args, &block)
    num = count - 1

    return first.to_s if num < 1

    sep = []

    if block_given?
      num.times do |i|
        sep << yield(i, *slice(i, 2))
      end
    else
      options = (Hash === args.last) ? args.pop : {}
      separator = args.shift || ""
      options[-1] = args.shift unless args.empty?

      sep = [separator] * num

      if options.key?(:last)
        options[-1] = options.delete(:last)
      end
      options[-1] ||= _(" and ")

      options.each{ |i, s| sep[i] = s }
    end

    zip(sep).join
  end
end

# Extensions to the Range class
#
class ::Range

  # This method returns a random number between the lower and upper bound
  #
  def pick_one
    len = self.last - self.first
    len += 1 unless self.exclude_end?
    self.first + Kernel::rand(len)
  end
  alias :rand :pick_one
end

# Extensions for the Numeric classes
#
class ::Numeric

  # This method forces a real number to be not more than a given positive
  # number or not less than a given positive number, or between two any given
  # numbers
  #
  def clip(left,right=0)
    raise ArgumentError unless left.kind_of?(Numeric) and right.kind_of?(Numeric)
    l = [left,right].min
    u = [left,right].max
    return l if self < l
    return u if self > u
    return self
  end
end

# Extensions to the String class
#
# TODO make riphtml() just call ircify_html() with stronger purify options.
#
class ::String

  # This method will return a purified version of the receiver, with all HTML
  # stripped off and some of it converted to IRC formatting
  #
  def ircify_html(opts={})
    txt = self.dup

    # remove scripts
    txt.gsub!(/<script(?:\s+[^>]*)?>.*?<\/script>/im, "")

    # remove styles
    txt.gsub!(/<style(?:\s+[^>]*)?>.*?<\/style>/im, "")

    # bold and strong -> bold
    txt.gsub!(/<\/?(?:b|strong)(?:\s+[^>]*)?>/im, "#{Bold}")

    # italic, emphasis and underline -> underline
    txt.gsub!(/<\/?(?:i|em|u)(?:\s+[^>]*)?>/im, "#{Underline}")

    ## This would be a nice addition, but the results are horrible
    ## Maybe make it configurable?
    # txt.gsub!(/<\/?a( [^>]*)?>/, "#{Reverse}")
    case val = opts[:a_href]
    when Reverse, Bold, Underline
      txt.gsub!(/<(?:\/a\s*|a (?:[^>]*\s+)?href\s*=\s*(?:[^>]*\s*)?)>/, val)
    when :link_out
      # Not good for nested links, but the best we can do without something like hpricot
      txt.gsub!(/<a (?:[^>]*\s+)?href\s*=\s*(?:([^"'>][^\s>]*)\s+|"((?:[^"]|\\")*)"|'((?:[^']|\\')*)')(?:[^>]*\s+)?>(.*?)<\/a>/) { |match|
        debug match
        debug [$1, $2, $3, $4].inspect
        link = $1 || $2 || $3
        str = $4
        str + ": " + link
      }
    else
      warning "unknown :a_href option #{val} passed to ircify_html" if val
    end

    # If opts[:img] is defined, it should be a String. Each image
    # will be replaced by the string itself, replacing occurrences of
    # %{alt} %{dimensions} and %{src} with the alt text, image dimensions
    # and URL
    if val = opts[:img]
      if val.kind_of? String
        txt.gsub!(/<img\s+(.*?)\s*\/?>/) do |imgtag|
          attrs = Hash.new
          imgtag.scan(/([[:alpha:]]+)\s*=\s*(['"])?(.*?)\2/) do |key, quote, value|
            k = key.downcase.intern rescue 'junk'
            attrs[k] = value
          end
          attrs[:alt] ||= attrs[:title]
          attrs[:width] ||= '...'
          attrs[:height] ||= '...'
          attrs[:dimensions] ||= "#{attrs[:width]}x#{attrs[:height]}"
          val % attrs
        end
      else
        warning ":img option is not a string"
      end
    end

    # Paragraph and br tags are converted to whitespace
    txt.gsub!(/<\/?(p|br)(?:\s+[^>]*)?\s*\/?\s*>/i, ' ')
    txt.gsub!("\n", ' ')
    txt.gsub!("\r", ' ')

    # Superscripts and subscripts are turned into ^{...} and _{...}
    # where the {} are omitted for single characters
    txt.gsub!(/<sup>(.*?)<\/sup>/, '^{\1}')
    txt.gsub!(/<sub>(.*?)<\/sub>/, '_{\1}')
    txt.gsub!(/(^|_)\{(.)\}/, '\1\2')

    # List items are converted to *). We don't have special support for
    # nested or ordered lists.
    txt.gsub!(/<li>/, ' *) ')

    # All other tags are just removed
    txt.gsub!(/<[^>]+>/, '')

    # Convert HTML entities. We do it now to be able to handle stuff
    # such as &nbsp;
    txt = Utils.decode_html_entities(txt)

    # Keep unbreakable spaces or conver them to plain spaces?
    case val = opts[:nbsp]
    when :space, ' '
      txt.gsub!([160].pack('U'), ' ')
    else
      warning "unknown :nbsp option #{val} passed to ircify_html" if val
    end

    # Remove double formatting options, since they only waste bytes
    txt.gsub!(/#{Bold}(\s*)#{Bold}/, '\1')
    txt.gsub!(/#{Underline}(\s*)#{Underline}/, '\1')

    # Simplify whitespace that appears on both sides of a formatting option
    txt.gsub!(/\s+(#{Bold}|#{Underline})\s+/, ' \1')
    txt.sub!(/\s+(#{Bold}|#{Underline})\z/, '\1')
    txt.sub!(/\A(#{Bold}|#{Underline})\s+/, '\1')

    # And finally whitespace is squeezed
    txt.gsub!(/\s+/, ' ')
    txt.strip!

    if opts[:limit] && txt.size > opts[:limit]
      txt = txt.slice(0, opts[:limit]) + "#{Reverse}...#{Reverse}"
    end

    # Decode entities and strip whitespace
    return txt
  end

  # As above, but modify the receiver
  #
  def ircify_html!(opts={})
    old_hash = self.hash
    replace self.ircify_html(opts)
    return self unless self.hash == old_hash
  end

  # This method will strip all HTML crud from the receiver
  #
  def riphtml
    self.gsub(/<[^>]+>/, '').gsub(/&amp;/,'&').gsub(/&quot;/,'"').gsub(/&lt;/,'<').gsub(/&gt;/,'>').gsub(/&ellip;/,'...').gsub(/&apos;/, "'").gsub("\n",'')
  end

  # This method tries to find an HTML title in the string,
  # and returns it if found
  def get_html_title
    if defined? ::Hpricot
      Hpricot(self).at("title").inner_html
    else
      return unless Irc::Utils::TITLE_REGEX.match(self)
      $1
    end
  end

  # This method returns the IRC-formatted version of an
  # HTML title found in the string
  def ircify_html_title
    self.get_html_title.ircify_html rescue nil
  end

  # This method is used to wrap a nonempty String by adding
  # the prefix and postfix
  def wrap_nonempty(pre, post, opts={})
    if self.empty?
      String.new
    else
      "#{pre}#{self}#{post}"
    end
  end
end


# Extensions to the Regexp class, with some common and/or complex regular
# expressions.
#
class ::Regexp

  # A method to build a regexp that matches a list of something separated by
  # optional commas and/or the word "and", an optionally repeated prefix,
  # and whitespace.
  def Regexp.new_list(reg, pfx = "")
    if pfx.kind_of?(String) and pfx.empty?
      return %r(#{reg}(?:,?(?:\s+and)?\s+#{reg})*)
    else
      return %r(#{reg}(?:,?(?:\s+and)?(?:\s+#{pfx})?\s+#{reg})*)
    end
  end

  IN_ON = /in|on/

  module Irc
    # Match a list of channel anmes separated by optional commas, whitespace
    # and optionally the word "and"
    CHAN_LIST = Regexp.new_list(GEN_CHAN)

    # Match "in #channel" or "on #channel" and/or "in private" (optionally
    # shortened to "in pvt"), returning the channel name or the word 'private'
    # or 'pvt' as capture
    IN_CHAN = /#{IN_ON}\s+(#{GEN_CHAN})|(here)|/
    IN_CHAN_PVT = /#{IN_CHAN}|in\s+(private|pvt)/

    # As above, but with channel lists
    IN_CHAN_LIST_SFX = Regexp.new_list(/#{GEN_CHAN}|here/, IN_ON)
    IN_CHAN_LIST = /#{IN_ON}\s+#{IN_CHAN_LIST_SFX}|anywhere|everywhere/
    IN_CHAN_LIST_PVT_SFX = Regexp.new_list(/#{GEN_CHAN}|here|private|pvt/, IN_ON)
    IN_CHAN_LIST_PVT = /#{IN_ON}\s+#{IN_CHAN_LIST_PVT_SFX}|anywhere|everywhere/

    # Match a list of nicknames separated by optional commas, whitespace and
    # optionally the word "and"
    NICK_LIST = Regexp.new_list(GEN_NICK)

  end

end


module ::Irc


  class BasicUserMessage

    # We extend the BasicUserMessage class with a method that parses a string
    # which is a channel list as matched by IN_CHAN(_LIST) and co. The method
    # returns an array of channel names, where 'private' or 'pvt' is replaced
    # by the Symbol :"?", 'here' is replaced by the channel of the message or
    # by :"?" (depending on whether the message target is the bot or a
    # Channel), and 'anywhere' and 'everywhere' are replaced by Symbol :*
    #
    def parse_channel_list(string)
      return [:*] if [:anywhere, :everywhere].include? string.to_sym
      string.scan(
      /(?:^|,?(?:\s+and)?\s+)(?:in|on\s+)?(#{Regexp::Irc::GEN_CHAN}|here|private|pvt)/
                 ).map { |chan_ar|
        chan = chan_ar.first
        case chan.to_sym
        when :private, :pvt
          :"?"
        when :here
          case self.target
          when Channel
            self.target.name
          else
            :"?"
          end
        else
          chan
        end
      }.uniq
    end

    # The recurse depth of a message, for fake messages. 0 means an original
    # message
    def recurse_depth
      unless defined? @recurse_depth
        @recurse_depth = 0
      end
      @recurse_depth
    end

    # Set the recurse depth of a message, for fake messages. 0 should only
    # be used by original messages
    def recurse_depth=(val)
      @recurse_depth = val
    end
  end

  class Bot
    module Plugins

      # Maximum fake message recursion
      MAX_RECURSE_DEPTH = 10

      class RecurseTooDeep < RuntimeError
      end

      class BotModule
        # Sometimes plugins need to create a new fake message based on an existing
        # message: for example, this is done by alias, linkbot, reaction and remotectl.
        #
        # This method simplifies the message creation, including a recursion depth
        # check.
        #
        # In the options you can specify the :bot, the :server, the :source,
        # the :target, the message :class and whether or not to :delegate. To
        # initialize these entries from an existing message, you can use :from
        #
        # Additionally, if :from is given, the reply method of created message
        # is overriden to reply to :from instead. The #in_thread attribute
        # for created mesage is also copied from :from
        #
        # If you don't specify a :from you should specify a :source.
        #
        def fake_message(string, opts={})
          if from = opts[:from]
            o = {
              :bot => from.bot, :server => from.server, :source => from.source,
              :target => from.target, :class => from.class, :delegate => true,
              :depth => from.recurse_depth + 1
            }.merge(opts)
          else
            o = {
              :bot => @bot, :server => @bot.server, :target => @bot.myself,
              :class => PrivMessage, :delegate => true, :depth => 1
            }.merge(opts)
          end
          raise RecurseTooDeep if o[:depth] > MAX_RECURSE_DEPTH
          new_m = o[:class].new(o[:bot], o[:server], o[:source], o[:target], string)
          new_m.recurse_depth = o[:depth]
          if from
            # the created message will reply to the originating message
            class << new_m
              self
            end.send(:define_method, :reply) do |*args|
              debug "replying to '#{from.message}' with #{args.first}"
              from.reply(*args)
            end
            # the created message will follow originating message's in_thread
            new_m.in_thread = from.in_thread if from.respond_to?(:in_thread)
          end
          return new_m unless o[:delegate]
          method = o[:class].to_s.gsub(/^Irc::|Message$/,'').downcase
          method = 'privmsg' if method == 'priv'
          o[:bot].plugins.irc_delegate(method, new_m)
        end
      end
    end
  end
end
