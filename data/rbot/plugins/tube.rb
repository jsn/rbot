#Tube Status Enquiry plugin for rbot
#Plugin by Colm Linehan

class TubePlugin < Plugin
  def help(plugin, topic="")
  "tube [district|circle|metropolitan|central|jubilee|bakerloo|waterlooandcity|hammersmithandcity|victoria|eastlondon|northern|piccadilly] => display tube service status for the specified line(Docklands Light Railway is not currently supported)" # , tube stations => list tube stations (not lines) with problems"
  end

  def tube(m, params)
    line = params[:line]
    tube_page = @bot.httputil.get('http://www.tfl.gov.uk/tfl/livetravelnews/realtime/tube/default.html')
    unless tube_page
      m.reply "Cannot contact Tube Service Status page"
      return
    end
    next_line = false
    tube_page.each_line {|l|
      next if l == "\r\n"
      next if l == "\n"
      if (next_line)
        if (l =~ /^<p>\s*(.*)<\/p>/i)
          m.reply $1.split(/<[^>]+>|&nbsp;/i).join(" ")
          return
        elsif l =~ /ul|h3|"message"/
          next
        else
          m.reply "There are problems on the #{line} line, but I didn't understand the page format. You should check out http://www.tfl.gov.uk/tfl/livetravelnews/realtime/tube/default.html for more details."
          return
        end
      end
      next_line = true if (l =~ /li class="#{line}"/i)
    }
    m.reply "No Problems on the #{line} line."
  end

  def check_stations(m, params)
    tube_page = @bot.httputil.get('http://www.tfl.gov.uk/tfl/service_rt_tube.shtml')
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
# plugin.map 'tube stations', :action => 'check_stations'
plugin.map 'tube :line'
