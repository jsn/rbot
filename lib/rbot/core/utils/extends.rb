#-- vim:sw=2:et
#++
#
# :title: Standard classes extensions
#
# Author:: Giuseppe "Oblomov" Bilotta <giuseppe.bilotta@gmail.com>
# Copyright:: (C) 2006,2007 Giuseppe Bilotta
# License:: GPL v2
#
# This file collects extensions to standard Ruby classes and to some core rbot
# classes to be used by the various plugins
#
# Please note that global symbols have to be prefixed by :: because this plugin
# will be read into an anonymous module


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
end


# Extensions to the String class
#
# TODO make ircify_html() accept an Hash of options, and make riphtml() just
# call ircify_html() with stronger purify options.
#
class ::String

  # This method will return a purified version of the receiver, with all HTML
  # stripped off and some of it converted to IRC formatting
  #
  def ircify_html
    txt = self

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

    # Paragraph and br tags are converted to whitespace
    txt.gsub!(/<\/?(p|br)(?:\s+[^>]*)?\s*\/?\s*>/, ' ')
    txt.gsub!("\n", ' ')
    txt.gsub!("\r", ' ')

    # All other tags are just removed
    txt.gsub!(/<[^>]+>/, '')

    # Convert HTML entities. We do it now to be able to handle stuff
    # such as &nbsp;
    txt = Utils.decode_html_entities(txt)

    # Remove double formatting options, since they only waste bytes
    txt.gsub!(/#{Bold}(\s*)#{Bold}/, '\1')
    txt.gsub!(/#{Underline}(\s*)#{Underline}/, '\1')

    # Simplify whitespace that appears on both sides of a formatting option
    txt.gsub!(/\s+(#{Bold}|#{Underline})\s+/, ' \1')
    txt.sub!(/\s+(#{Bold}|#{Underline})\z/, '\1')
    txt.sub!(/\A(#{Bold}|#{Underline})\s+/, '\1')

    # And finally whitespace is squeezed
    txt.gsub!(/\s+/, ' ')

    # Decode entities and strip whitespace
    return txt.strip
  end

  # This method will strip all HTML crud from the receiver
  #
  def riphtml
    self.gsub(/<[^>]+>/, '').gsub(/&amp;/,'&').gsub(/&quot;/,'"').gsub(/&lt;/,'<').gsub(/&gt;/,'>').gsub(/&ellip;/,'...').gsub(/&apos;/, "'").gsub("\n",'')
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
  end
end
