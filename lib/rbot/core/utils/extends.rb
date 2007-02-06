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
    txt.gsub!(/#{Bold}\s*#{Bold}/,"")
    txt.gsub!(/#{Underline}\s*#{Underline}/,"")

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


