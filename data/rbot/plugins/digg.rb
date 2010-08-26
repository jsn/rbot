# Hacked up digg headlines plugin...

require 'time'
require 'rexml/document'
require 'uri/common'

class DiggPlugin < Plugin
  include REXML
  def help(plugin, topic="")
    "digg [<max>=5] => show digg headlines, [<max>=5] => return up to <max> headlines (use a negative number to show all the headlines on one line)"
  end

  def digg(m, params)
    max = params[:limit].to_i
    debug "max is #{max}"
    xml = @bot.httputil.get('http://services.digg.com/2.0/story.getTopNews?type=rss')
    unless xml
      m.reply "digg news unavailable"
      return
    end
    doc = Document.new xml
    unless doc
      m.reply "digg news parse failed (invalid xml)"
      return
    end
    done = 0
    oneline = false
    if max < 0
      max = (0 - max)
      oneline = true
    end
    max = 8 if max > 8
    matches = Array.new
    doc.elements.each("rss/channel/item") {|e|
      matches << [ e.elements["title"].text.strip,
                   Time.parse(e.elements["pubDate"].text).strftime('%a @ %I:%M%p') ]
      done += 1
      break if done >= max
    }
    if oneline
      m.reply matches.collect{|mat| mat[0]}.join(" | ")
    else
      matches.each {|mat|
        m.reply sprintf("%42s | %13s", mat[0][0,42], mat[1])
      }
    end
  end
end
plugin = DiggPlugin.new
plugin.map 'digg :limit', :defaults => {:limit => 5},
                          :requirements => {:limit => /^-?\d+$/}
