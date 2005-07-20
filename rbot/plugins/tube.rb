#Tube Status Enquiry plugin for rbot
#Plugin by Colm Linehan

require 'rexml/document'
require 'uri/common'

class TubePlugin < Plugin
  include REXML
  def help(plugin, topic="")
  "tube [district|circle|metropolitan|central|jubilee|bakerloo|waterloo_city|hammersmith_city|victoria|eastlondon|northern|piccadilly] => display tube service status for the specified line(Docklands Light Railway is not currently supported), tube stations => list tube stations (not lines) with problems"
  end
  def privmsg(m)
  if m.params && m.params =~ /^stations$/
    check_stations m
  elsif m.params && m.params =~ /^(.*)$/
    line = $1.downcase.capitalize
    check_tube m, line
  end
  end
  
  def check_tube(m, line)
  begin
    tube_page = @bot.httputil.get(URI.parse("http://www.tfl.gov.uk/tfl/service_rt_tube.shtml"), 1, 1)
  rescue URI::InvalidURIError, URI::BadURIError => e
    m.reply "Cannot contact Tube Service Status page"
    return
  end
  unless tube_page
    m.reply "Cannot contact Tube Service Status page"
    return
  end
  tube_page.each_line {|l|
      if (l =~ /class="#{line}"/i)
        tube_page.each_line { |l2|
        if (l2 =~ /^<tr valign=top> <td>\s*(.*#{line}.*)<\/td><\/tr>/i)
          problem_message = Array.new
          problem_message = $1.split(/<[^>]+>|&nbsp;/i)
          m.reply problem_message.join(" ")
          return
        end
        }
        m.reply "There are problems on the #{line} line, but I didn't understand the page format. You should check out http://www.tfl.gov.uk/tfl/service_rt_tube.shtml for more details."
        return
      end
      }
  m.reply "No Problems on the #{line} line."
  end

  def check_stations(m)
    begin
      tube_page = Utils.http_get("http://www.tfl.gov.uk/tfl/service_rt_tube.shtml")
    rescue URI::InvalidURIError, URI::BadURIError => e
      m.reply "Cannot contact Tube Service Status page"
      return
    end
    unless tube_page
      m.reply "Cannot contact Tube Service Status page"
      return
    end
    stations_array = Array.new
    tube_page.each_line {|l|
        if (l =~ /<tr valign=top> <td valign="middle" class="Station"><b>(.*)<\/b><\/td><\/tr>\s*/i)
          stations_array.push $1
        end
        }
    if stations_array.empty? 
      m.reply "There are no station-specific announcements"
      return
    else
      m.reply stations_array.join(", ")
      return
    end
  end
end
plugin = TubePlugin.new
plugin.register("tube")
