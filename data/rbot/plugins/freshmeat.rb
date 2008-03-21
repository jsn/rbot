#-- vim:sw=2:et
#++
#
# :title: Freshmeat plugin for rbot

require 'rexml/document'

class FreshmeatPlugin < Plugin
  include REXML
  def help(plugin, topic="")
    "freshmeat search [<max>=4] <string> => search freshmeat for <string>, freshmeat [<max>=4] => return up to <max> freshmeat headlines"
  end

  REL_ENTRY = %r{<a href="/(release)s/(\d+)/"><font color="#000000">(.*?)</font></a>}
  PRJ_ENTRY = %r{<a href="/(project)s/(\S+?)/"><b>(.*?)</b></a>}

  # This method defines a filter for fm pages. It's needed because the generic
  # summarization grabs a comment, not the actual article.
  #
  def freshmeat_filter(s)
    loc = Utils.check_location(s, /freshmeat\.net/)
    return nil unless loc
    entries = []
    s[:text].scan(/#{REL_ENTRY}|#{PRJ_ENTRY}/) { |m|
      entry = {
        :type => ($1 || $4).dup,
        :code => ($2 || $5).dup,
        :name => ($3 || $6).dup
      }
      entries << entry
    }
    return nil if entries.empty?
    title = s[:text].ircify_html_title
    content = entries.inject([]) { |l, e| l << e[:name] }.join(" | ")
    return {:title => title, :content => content}
  end

  def initialize
    super
    @bot.register_filter(:freshmeat, :htmlinfo) { |s| freshmeat_filter(s) }
  end

  def search_freshmeat(m, params)
    max = params[:limit].to_i
    search = params[:search].to_s
    max = 8 if max > 8
    xml = @bot.httputil.get("http://freshmeat.net/search-xml/?orderby=locate_projectname_full_DESC&q=#{CGI.escape(search)}")
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
  
  def freshmeat(m, params)
    max = params[:limit].to_i
    max = 8 if max > 8
    begin
      xml = @bot.httputil.get('http://images.feedstermedia.com/feedcache/ostg/freshmeat/fm-releases-global.xml')
      unless xml
        m.reply "freshmeat news parse failed"
        return
      end
      doc = Document.new xml
      unless doc
        m.reply "freshmeat news parse failed"
        return
      end
    rescue
      m.reply "freshmeat news parse failed"
      return
    end

    matches = Array.new
    max_width = 60
    title_width = 0
    done = 0
    doc.elements.each("*/channel/item") {|e|
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
      #desc = mat[1]
      #desc.gsub!(/(.{#{max_width - 3 - title_width}}).*/, '\1..')
      #reply = sprintf("%#{title_width}s | %s", title, desc)
      m.reply title
    }
  end
end
plugin = FreshmeatPlugin.new
plugin.map 'freshmeat search :limit *search', :action => 'search_freshmeat',
            :defaults => {:limit => 4}, :requirements => {:limit => /^\d+$/}
plugin.map 'freshmeat :limit', :defaults => {:limit => 4}, 
                               :requirements => {:limit => /^\d+$/}
