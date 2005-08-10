# Security threat level plugin for rbot
# by Robin Kearney (robin@riviera.org.uk)
#
# inspired by elliots fascination with the us
# threat level.
#
# again a dirty hack but it works, just...
#

require 'uri/common'

class ThreatPlugin < Plugin

  def help(plugin, topic="")
    "threat => prints out the current threat level as reported by http://www.dhs.gov/"
  end

  def privmsg(m)
	color = ""
    red = "\x0304" # severe
	orange = "\x0307" # high
	yellow = "\x0308" # elevated
	blue = "\x0312" # guarded
	green = "\x0303" # low
	black = "\x0301" # default

	page = @bot.httputil.get URI.parse("http://www.dhs.gov/dhspublic/")
	if page =~ / <img.*dhs\/images\/dhs-advisory-(.*).gif.*/
      state = $1
    end
    case state
      when "severe"
		color = red
      when "high"
		color = orange
      when "elevated"
		color = yellow
      when "guarded"
		color = blue
      when "low"
		color = green
	else
	  color = black
	end

	m.reply color + "Today " + m.sourcenick + " the threat level is " + state.capitalize

	return
  end

end
plugin = ThreatPlugin.new
plugin.register("threat")


