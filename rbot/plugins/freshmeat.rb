require 'rexml/document'
require 'uri/common'

class FreshmeatPlugin < Plugin
  include REXML
  def help(plugin, topic="")
    "freshmeat search <string> [<max>=4] => search freshmeat for <string>, freshmeat [<max>=4] => return up to <max> freshmeat headlines"
  end
  def privmsg(m)
    if m.params && m.params =~ /^search\s+(.*)\s+(\d+)$/
      search = $1
      limit = $2.to_i
      search_freshmeat m, search, limit
    elsif m.params && m.params =~ /^search\s+(.*)$/
      search = $1
      search_freshmeat m, search
    elsif m.params && m.params =~ /^(\d+)$/
      limit = $1.to_i
      freshmeat m, limit
    else
      freshmeat m
    end
  end
  
  def search_freshmeat(m, search, max=4)
    max = 8 if max > 8
    begin
      xml = Utils.http_get("http://freshmeat.net/search-xml/?orderby=locate_projectname_full_DESC&q=#{URI.escape(search)}")
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
    matches = Array.new
    max_width = 250
    title_width = 0
    url_width = 0
    done = 0
    doc.elements.each("*/match") {|e|
      name = e.elements["projectname_short"].text
      url = "http://freshmeat.net/projects/#{name}/"
      desc = e.elements["desc_short"].text
      title = e.elements["projectname_full"].text
      #title_width = title.length if title.length > title_width
      url_width = url.length if url.length > url_width
      matches << [title, url, desc]
      done += 1
      break if done >= max
    }
    if matches.length == 0
      m.reply "not found: #{search}"
    end
    matches.each {|mat|
      title = mat[0]
      url = mat[1]
      desc = mat[2]
      desc.gsub!(/(.{#{max_width - 3 - url_width}}).*/, '\1..')
      reply = sprintf("%s | %s", url.ljust(url_width), desc)
      m.reply reply
    }
  end
  
  def freshmeat(m, max=4)
    max = 8 if max > 8
    xml = Utils.http_get("http://download.freshmeat.net/backend/fm-releases-software.rdf")
    unless xml
      m.reply "freshmeat news parse failed"
      return
    end
    doc = Document.new xml
    unless doc
      m.reply "freshmeat news parse failed"
      return
    end
    matches = Array.new
    max_width = 60
    title_width = 0
    done = 0
    doc.elements.each("*/item") {|e|
      desc = e.elements["description"].text
      title = e.elements["title"].text
      #title.gsub!(/\s+\(.*\)\s*$/, "")
      title.strip!
      title_width = title.length if title.length > title_width
      matches << [title, desc]
      done += 1
      break if done >= max
    }
    matches.each {|mat|
      title = mat[0]
      desc = mat[1]
      desc.gsub!(/(.{#{max_width - 3 - title_width}}).*/, '\1..')
      reply = sprintf("%#{title_width}s | %s", title, desc)
      m.reply reply
    }
  end
end
plugin = FreshmeatPlugin.new
plugin.register("freshmeat")
