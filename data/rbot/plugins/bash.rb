# bash.org xml plugin for rbot
# by Robin Kearney (robin@riviera.org.uk)
#
# its a bit of a quick hack, but it works for us :)
#
require 'rexml/document'
require 'uri/common'

class BashPlugin < Plugin
  include REXML
  def help(plugin, topic="")
    "bash => print a random quote from bash.org, bash quote_id => print that quote id from bash.org, bash latest => print the latest quote from bash.org (currently broken, need to get josh@bash.org to fix the xml)"
  end
  def privmsg(m)
    if m.params && m.params =~ /^([-\d]+)$/
      id = $1
      bash m, id
	elsif(m.params == "latest")
	  bash m, id
    else
      bash m
    end
  end
  
  def bash(m, id=0)

	if(id != 0)
    	xml = @bot.httputil.get URI.parse("http://bash.org/xml/?" + id + "&num=1")
	elsif(id == "latest")
    	xml = @bot.httputil.get URI.parse("http://bash.org/xml/?latest&num=1")
	else
    	xml = @bot.httputil.get URI.parse("http://bash.org/xml/?random&num=1")
	end	
    unless xml
      m.reply "bash.org rss parse failed"
      return
    end
    doc = Document.new xml
    unless doc
      m.reply "bash.org rss parse failed"
      return
    end
	doc.elements.each("*/item") {|e|
		if(id != 0) 
			reply = e.elements["title"].text.gsub(/QDB: /,"") + " " + e.elements["link"].text.gsub(/QDB: /,"") + "\n"
			reply = reply + e.elements["description"].text.gsub(/\<br \/\>/, "\n")
		else
			reply = e.elements["title"].text.gsub(/QDB: /,"") + " " + e.elements["link"].text.gsub(/QDB: /,"") + "\n"
			reply = reply + e.elements["description"].text.gsub(/\<br \/\>/, "\n")
		end
		m.reply reply
	}
  end
end
plugin = BashPlugin.new
plugin.register("bash")
