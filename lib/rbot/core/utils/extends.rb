#-- vim:sw=2:et
#++
#
# Extensions to standard classes, to be used by the various plugins
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

    # bold and strong -> bold
    txt.gsub!(/<\/?(?:b|strong)\s*>/, "#{Bold}")

    # italic, emphasis and underline -> underline
    txt.gsub!(/<\/?(?:i|em|u)\s*>/, "#{Underline}")

    ## This would be a nice addition, but the results are horrible
    ## Maybe make it configurable?
    # txt.gsub!(/<\/?a( [^>]*)?>/, "#{Reverse}")

    # Paragraph and br tags are converted to whitespace.
    txt.gsub!(/<\/?(p|br)\s*\/?\s*>/, ' ')
    txt.gsub!("\n", ' ')

    # All other tags are just removed
    txt.gsub!(/<[^>]+>/, '')

    # Remove double formatting options, since they only waste bytes
    txt.gsub!(/#{Bold}(\s*)#{Bold}/, '\1')
    txt.gsub!(/#{Underline}(\s*)#{Underline}/, '\1')

    # And finally whitespace is squeezed
    txt.gsub!(/\s+/, ' ')

    # Decode entities and strip whitespace
    return Utils.decode_html_entities(txt).strip!
  end

  # This method will strip all HTML crud from the receiver
  #
  def riphtml
    self.gsub(/<[^>]+>/, '').gsub(/&amp;/,'&').gsub(/&quot;/,'"').gsub(/&lt;/,'<').gsub(/&gt;/,'>').gsub(/&ellip;/,'...').gsub(/&apos;/, "'").gsub("\n",'')
  end
end

# Extensions to the Regexp class, with some commonly used regular expressions.
#
module ::Rx


  # We start with some IRC related regular expressions, used to match
  # Irc::User nicks and Irc::Channel names
  #
  # For each of them we define three versions of the regular expression:
  #  * a generic one, which should match for any server but may turn out to match
  #    more than a specific server would accept
  #  * an RFC-compliant matcher
  #  * TODO a server-specific one that uses the Irc::Server#supports method to build
  #    a matcher valid for a particular server.
  #
  module Irc
    CHAN_FIRST = /[#&+]/
    CHAN_SAFE = /![A-Z0-9]{5}/
    CHAN_ANY = /[^\x00\x07\x0A\x0D ,:]/
    GENERIC_CHAN = /(?:#{CHAN_FIRST}|#{CHAN_SAFE})#{CHAN_ANY}+/
    RFC_CHAN = /#{CHAN_FIRST}#{CHAN_ANY}{1,49}|#{CHAN_SAFE}#{CHAN_ANY}{1,44}/

    SPECIAL_CHAR = /[\x5b-\x60\x7b-\x7d]/
    NICK_FIRST = /#{SPECIAL_CHAR}|[[:alpha:]]/
    NICK_ANY = /#{SPECIAL_CHAR}|[[:alnum:]]|-/
    GENERIC_NICK = /#{NICK_FIRST}#{NICK_ANY}+/
    RFC_NICK = /#{NICK_FIRST}#{NICK_ANY}{0,8}/
  end


  # Next, some general purpose ones
  DIGITS = /[0-9]+/
  HEX_DIGIT = /[0-9A-Za-z]/
  HEX_DIGITS = /#{HEX_DIGIT}+/
  HEX_OCTET = /#{HEX_DIGIT}#{HEX_DIGIT}?/
  DEC_OCTET = /[01]?[0-9]?[0-9]|2[0-4][0-9]|25[0-5]/
  DEC_IP = /#{DEC_OCTET}.#{DEC_OCTET}.#{DEC_OCTET}/
  HEX_IP = /#{HEX_OCTET}.#{HEX_OCTET}.#{HEX_OCTET}/
  IP = /#{DEC_IP}|#{HEX_IP}/

end


