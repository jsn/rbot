require 'rexml/document'
require 'uri/common'

class SlashdotPlugin < Plugin
  include REXML
  def help(plugin, topic="")
    "slashdot search <string> [<max>=4] => search slashdot for <string>, slashdot [<max>=4] => return up to <max> slashdot headlines (use negative max to return that many headlines, but all on one line.)"
  end
  def privmsg(m)
    if m.params && m.params =~ /^search\s+(.*)\s+(\d+)$/
      search = $1
      limit = $2.to_i
      search_slashdot m, search, limit
    elsif m.params && m.params =~ /^search\s+(.*)$/
      search = $1
      search_slashdot m, search
    elsif m.params && m.params =~ /^([-\d]+)$/
      limit = $1.to_i
      slashdot m, limit
    else
      slashdot m
    end
  end
  
  def search_slashdot(m, search, max=4)
    begin
      xml = Utils.http_get("http://slashdot.org/search.pl?content_type=rss&query=#{URI.escape(search)}")
    rescue URI::InvalidURIError, URI::BadURIError => e
      m.reply "illegal search string #{search}"
      return
    end
    unless xml
      m.reply "search for #{search} failed"
      return
    end
    doc = Document.new xml
    unless doc
      m.reply "search for #{search} failed"
      return
    end
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
  end
  
  def slashdot(m, max=4)
    xml = Utils.http_get("http://slashdot.org/slashdot.xml")
    unless xml
      m.reply "slashdot news parse failed"
      return
    end
    doc = Document.new xml
    unless doc
      m.reply "slashdot news parse failed"
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
plugin.register("slashdot")
