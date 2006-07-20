require 'rexml/document'
require 'uri/common'

class SlashdotPlugin < Plugin
  include REXML
  def help(plugin, topic="")
    "slashdot search <string> [<max>=4] => search slashdot for <string>, slashdot [<max>=4] => return up to <max> slashdot headlines (use negative max to return that many headlines, but all on one line.)"
  end
  
  def search_slashdot(m, params)
   max = params[:limit].to_i
   search = params[:search].to_s

    begin
      xml = @bot.httputil.get(URI.parse("http://slashdot.org/search.pl?content_type=rss&query=#{URI.escape(search)}"))
    rescue URI::InvalidURIError, URI::BadURIError => e
      m.reply "illegal search string #{search}"
      return
    end
    unless xml
      m.reply "search for #{search} failed"
      return
    end
    debug xml.inspect
    begin
      doc = Document.new xml
    rescue REXML::ParseException => e
      warning e.inspect
      m.reply "couldn't parse output XML: #{e.class}"
      return
    end
    unless doc
      m.reply "search for #{search} failed"
      return
    end
    debug doc.inspect
    max = 8 if max > 8
    done = 0
    doc.elements.each("*/item") {|e|
      desc = e.elements["title"].text
      desc.gsub!(/(.{150}).*/, '\1..')
      reply = sprintf("%s | %s", e.elements["link"].text, desc)
      m.reply reply
      done += 1
      break if done >= max
    }
    unless done > 0
      m.reply "search for #{search} failed"
    end
  end
  
  def slashdot(m, params)
    debug params.inspect
    max = params[:limit].to_i
    debug "max is #{max}"
    xml = @bot.httputil.get(URI.parse("http://slashdot.org/slashdot.xml"))
    unless xml
      m.reply "slashdot news parse failed"
      return
    end
    doc = Document.new xml
    unless doc
      m.reply "slashdot news parse failed (invalid xml)"
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
    doc.elements.each("*/story") {|e|
      matches << [ e.elements["title"].text, 
                   e.elements["author"].text, 
                   e.elements["time"].text.gsub(/\d{4}-(\d{2})-(\d{2})/, "\\2/\\1").gsub(/:\d\d$/, "") ]
      done += 1
      break if done >= max
    } 
    if oneline
      m.reply matches.collect{|mat| mat[0]}.join(" | ")
    else
      matches.each {|mat|
        m.reply sprintf("%36s | %8s | %8s", mat[0][0,36], mat[1][0,8], mat[2])
      }
    end
  end
end
plugin = SlashdotPlugin.new
plugin.map 'slashdot search :limit *search', :action => 'search_slashdot',
           :defaults => {:limit => 4}, :requirements => {:limit => /^-?\d+$/}
plugin.map 'slashdot :limit', :defaults => {:limit => 4},
                              :requirements => {:limit => /^-?\d+$/}
