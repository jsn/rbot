# RSS feed plugin for RubyBot
# (c) 2004 Stanislav Karchebny <berkus@madfire.net>
# (c) 2005 Ian Monroe <ian@monroe.nu>
# (c) 2005 Mark Kretschmann <markey@web.de>
# Licensed under MIT License.

require 'rss/parser'
require 'rss/1.0'
require 'rss/2.0'
require 'rss/dublincore'
begin
  # require 'rss/dublincore/2.0'
rescue
  warning "Unable to load RSS libraries, RSS plugin functionality crippled"
end

class ::String
  def shorten(limit)
    if self.length > limit
      self+". " =~ /^(.{#{limit}}[^.!;?]*[.!;?])/mi
      return $1
    end
    self
  end

  def riphtml
    self.gsub(/<[^>]+>/, '').gsub(/&amp;/,'&').gsub(/&quot;/,'"').gsub(/&lt;/,'<').gsub(/&gt;/,'>').gsub(/&ellip;/,'...').gsub(/&apos;/, "'").gsub("\n",'')
  end

  def mysqlize
    self.gsub(/'/, "''")
  end
end

class ::RssBlob
  attr :url
  attr :handle
  attr :type
  attr :watchers

  def initialize(url,handle=nil,type=nil,watchers=[])
    @url = url
    if handle
      @handle = handle
    else
      @handle = url
    end
    @type = type
    @watchers = watchers
  end

  def watched?
    !@watchers.empty?
  end

  def watched_by?(who)
    @watchers.include?(who)
  end

  def add_watch(who)
    if watched_by?(who)
      return nil
    end
    @watchers << who unless watched_by?(who)
    return who
  end

  def rm_watch(who)
    @watchers.delete(who)
  end

  #  def to_ary
  #    [@handle,@url,@type,@watchers]
  #  end
end

class RSSFeedsPlugin < Plugin
  @@watchThreads = Hash.new
  @@mutex = Mutex.new

  def initialize
    super
    kill_threads
    if @registry.has_key?(:feeds)
      @feeds = @registry[:feeds]
    else
      @feeds = Hash.new
    end
    rewatch_rss
  end

  def watchlist
    @feeds.select { |h, f| f.watched? }
  end

  def cleanup
    kill_threads
  end

  def save
    @registry[:feeds] = @feeds
  end

  def kill_threads
    @@mutex.synchronize {
      # Abort all running threads.
      @@watchThreads.each { |url, thread|
        debug "Killing thread for #{url}"
        thread.kill
      }
      @@watchThreads = Hash.new
    }
  end

  def help(plugin,topic="")
    case topic
    when "show"
      "rss show +handle+ [+limit+] : show +limit+ (default: 5, max: 15) entries from rss +handle+"
    when "list"
      "rss list [+handle+] : list all rss feeds (matching +handle+)"
    when "watched"
      "rss watched [+handle+] : list all watched rss feeds (matching +handle+)"
    when "add"
      "rss add +handle+ +url+ [+type+] : add a new rss called +handle+ from url +url+ (of type +type+)"
    when /^(del(ete)?|rm)$/
      "rss del(ete)|rm +handle+ : delete rss feed +handle+"
    when "replace"
      "rss replace +handle+ +url+ [+type+] : try to replace the url of rss called +handle+ with +url+ (of type +type+); only works if nobody else is watching it"
    when "forcereplace"
      "rss forcereplace +handle+ +url+ [+type+] : replace the url of rss called +handle+ with +url+ (of type +type+)"
    when "watch"
      "rss watch +handle+ [+url+ [+type+]] : watch rss +handle+ for changes; when the other parameters are present, it will be created if it doesn't exist yet"
    when /(un|rm)watch/
      "rss unwatch|rmwatch +handle+ : stop watching rss +handle+ for changes"
    when "rewatch"
      "rss rewatch : restart threads that watch for changes in watched rss"
    else
      "manage RSS feeds: rss show|list|watched|add|del(ete)|rm|(force)replace|watch|unwatch|rmwatch|rewatch"
    end
  end

  def report_problem(report, m=nil)
    if m
      m.reply report
    else
      warning report
    end
  end

  def show_rss(m, params)
    handle = params[:handle]
    limit = params[:limit].to_i
    limit = 15 if limit > 15
    limit = 1 if limit <= 0
    feed = @feeds.fetch(handle, nil)
    unless feed
      m.reply "I don't know any feeds named #{handle}"
      return
    end
    m.reply("Please wait, querying...")
    title = items = nil
    @@mutex.synchronize {
      title, items = fetchRss(feed, m)
    }
    return unless items
    m.reply("Channel : #{title}")
    # TODO: optional by-date sorting if dates present
    items[0...limit].reverse.each do |item|
      printRssItem(m.replyto,item)
    end
  end

  def list_rss(m, params)
    wanted = params[:handle]
    reply = String.new
    @@mutex.synchronize {
      @feeds.each { |handle, feed|
        next if wanted and !handle.match(wanted)
        reply << "#{feed.handle}: #{feed.url} (in format: #{feed.type ? feed.type : 'default'})"
        (reply << " (watched)") if feed.watched_by?(m.replyto)
        reply << "\n"
      }
    }
    if reply.empty?
      reply = "no feeds found"
      reply << " matching #{wanted}" if wanted
    end
    m.reply reply
  end

  def watched_rss(m, params)
    wanted = params[:handle]
    reply = String.new
    @@mutex.synchronize {
      watchlist.each { |handle, feed|
        next if wanted and !handle.match(wanted)
        next unless feed.watched_by?(m.replyto)
        reply << "#{feed.handle}: #{feed.url} (in format: #{feed.type ? feed.type : 'default'})\n"
      }
    }
    if reply.empty?
      reply = "no watched feeds"
      reply << " matching #{wanted}" if wanted
    end
    m.reply reply
  end

  def add_rss(m, params, force=false)
    handle = params[:handle]
    url = params[:url]
    type = params[:type]
    if @feeds.fetch(handle, nil) && !force
      m.reply "There is already a feed named #{handle} (URL: #{@feeds[handle].url})"
      return
    end
    unless url
      m.reply "You must specify both a handle and an url to add an RSS feed"
      return
    end
    @@mutex.synchronize {
      @feeds[handle] = RssBlob.new(url,handle,type)
    }
    reply = "Added RSS #{url} named #{handle}"
    if type
      reply << " (format: #{type})"
    end
    m.reply reply
    return handle
  end

  def del_rss(m, params, pass=false)
    feed = unwatch_rss(m, params, true)
    if feed.watched?
      m.reply "someone else is watching #{feed.handle}, I won't remove it from my list"
      return
    end
    @@mutex.synchronize {
      @feeds.delete(feed.handle)
    }
    m.okay unless pass
    return
  end

  def replace_rss(m, params)
    handle = params[:handle]
    if @feeds.key?(handle)
      del_rss(m, {:handle => handle}, true)
    end
    if @feeds.key?(handle)
      m.reply "can't replace #{feed.handle}"
    else
      add_rss(m, params, true)
    end
  end

  def forcereplace_rss(m, params)
    add_rss(m, params, true)
  end

  def watch_rss(m, params)
    handle = params[:handle]
    url = params[:url]
    type = params[:type]
    if url
      add_rss(m, params)
    end
    feed = nil
    @@mutex.synchronize {
      feed = @feeds.fetch(handle, nil)
    }
    if feed
      @@mutex.synchronize {
        if feed.add_watch(m.replyto)
          watchRss(feed, m)
          m.okay
        else
          m.reply "Already watching #{feed.handle}"
        end
      }
    else
      m.reply "Couldn't watch feed #{handle} (no such feed found)"
    end
  end

  def unwatch_rss(m, params, pass=false)
    handle = params[:handle]
    unless @feeds.has_key?(handle)
      m.reply("dunno that feed")
      return
    end
    feed = @feeds[handle]
    if feed.rm_watch(m.replyto)
      m.reply "#{m.replyto} has been removed from the watchlist for #{feed.handle}"
    else
      m.reply("#{m.replyto} wasn't watching #{feed.handle}") unless pass
    end
    if !feed.watched?
      @@mutex.synchronize {
        if @@watchThreads[handle].kind_of? Thread
          @@watchThreads[handle].kill
          debug "rmwatch: Killed thread for #{handle}"
          @@watchThreads.delete(handle)
        end
      }
    end
    return feed
  end

  def rewatch_rss(m=nil)
    kill_threads

    # Read watches from list.
    watchlist.each{ |handle, feed|
      watchRss(feed, m)
    }
    m.okay if m
  end

  private
  def watchRss(feed, m=nil)
    if @@watchThreads.has_key?(feed.handle)
      report_problem("watcher thread for #{feed.handle} is already running", m)
      return
    end
    @@watchThreads[feed.handle] = Thread.new do
      debug 'watchRss thread started.'
      oldItems = []
      firstRun = true
      loop do
        begin
          debug 'Fetching rss feed...'
          title = newItems = nil
          @@mutex.synchronize {
            title, newItems = fetchRss(feed)
          }
          unless newItems
            m.reply "no items in feed"
            break
          end
          debug "Checking if new items are available"
          if firstRun
            debug "First run, we'll see next time"
            firstRun = false
          else
            otxt = oldItems.map { |item| item.to_s }
            dispItems = newItems.reject { |item|
              otxt.include?(item.to_s)
            }
            if dispItems.length > 0
              debug "Found #{dispItems.length} new items"
              dispItems.each { |item|
                debug "showing #{item.title}"
                @@mutex.synchronize {
                  printFormattedRss(feed.watchers, item, feed.type)
                }
              }
            else
              debug "No new items found"
            end
          end
          oldItems = newItems.dup
        rescue Exception => e
          error "IO failed: #{e.inspect}"
          debug e.backtrace.join("\n")
        end

        seconds = 150 + rand(100)
        debug "Thread going to sleep #{seconds} seconds.."
        sleep seconds
      end
    end
  end

  def printRssItem(loc,item)
    if item.kind_of?(RSS::RDF::Item)
      @bot.say loc, item.title.chomp.riphtml.shorten(20) + " @ " + item.link
    else
      @bot.say loc, "#{item.pubDate.to_s.chomp+": " if item.pubDate}#{item.title.chomp.riphtml.shorten(20)+" :: " if item.title}#{" @ "+item.link.chomp if item.link}"
    end
  end

  def printFormattedRss(locs, item, type)
    locs.each { |loc|
      case type
      when 'amarokblog'
        @bot.say loc, "::#{item.category.content} just blogged at #{item.link}::"
        @bot.say loc, "::#{item.title.chomp.riphtml} - #{item.description.chomp.riphtml.shorten(60)}::"
      when 'amarokforum'
        @bot.say loc, "::Forum:: #{item.pubDate.to_s.chomp+": " if item.pubDate}#{item.title.chomp.riphtml+" :: " if item.title}#{" @ "+item.link.chomp if item.link}"
      when 'mediawiki'
        @bot.say loc, "::Wiki:: #{item.title} has been edited by #{item.dc_creator}. #{item.description.split("\n")[0].chomp.riphtml.shorten(60)} #{item.link} ::"
        debug "mediawiki #{item.title}"
      when "gmame"
        @bot.say loc, "::amarok-devel:: Message #{item.title} sent by #{item.dc_creator}. #{item.description.split("\n")[0].chomp.riphtml.shorten(60)}::"
      else
        printRssItem(loc,item)
      end
    }
  end

  def fetchRss(feed, m=nil)
    begin
      # Use 60 sec timeout, cause the default is too low
      xml = @bot.httputil.get_cached(feed.url,60,60)
    rescue URI::InvalidURIError, URI::BadURIError => e
      report_problem("invalid rss feed #{feed.url}", m)
      return
    end
    debug 'fetched'
    unless xml
      report_problem("reading feed #{url} failed", m)
      return
    end

    begin
      ## do validate parse
      rss = RSS::Parser.parse(xml)
      debug 'parsed'
    rescue RSS::InvalidRSSError
      ## do non validate parse for invalid RSS 1.0
      begin
        rss = RSS::Parser.parse(xml, false)
      rescue RSS::Error
        report_problem("parsing rss stream failed, whoops =(", m)
        return
      end
    rescue RSS::Error
      report_problem("parsing rss stream failed, oioi", m)
      return
    rescue => e
      report_problem("processing error occured, sorry =(", m)
      debug e.inspect
      debug e.backtrace.join("\n")
      return
    end
    items = []
    if rss.nil?
      report_problem("#{feed.url} does not include RSS 1.0 or 0.9x/2.0",m)
    else
      begin
        rss.output_encoding = "euc-jp"
      rescue RSS::UnknownConvertMethod
        report_problem("bah! something went wrong =(",m)
        return
      end
      rss.channel.title ||= "Unknown"
      title = rss.channel.title
      rss.items.each do |item|
        item.title ||= "Unknown"
        items << item
      end
    end

    if items.empty?
      report_problem("no items found in the feed, maybe try weed?",m)
      return
    end
    return [title, items]
  end
end

plugin = RSSFeedsPlugin.new

plugin.map 'rss show :handle :limit',
  :action => 'show_rss',
  :requirements => {:limit => /^\d+$/},
  :defaults => {:limit => 5}
plugin.map 'rss list :handle',
  :action => 'list_rss',
  :defaults =>  {:handle => nil}
plugin.map 'rss watched :handle',
  :action => 'watched_rss',
  :defaults =>  {:handle => nil}
plugin.map 'rss add :handle :url :type',
  :action => 'add_rss',
  :defaults => {:type => nil}
plugin.map 'rss del :handle',
  :action => 'del_rss'
plugin.map 'rss delete :handle',
  :action => 'del_rss'
plugin.map 'rss rm :handle',
  :action => 'del_rss'
plugin.map 'rss replace :handle :url :type',
  :action => 'replace_rss',
  :defaults => {:type => nil}
plugin.map 'rss forcereplace :handle :url :type',
  :action => 'forcereplace_rss',
  :defaults => {:type => nil}
plugin.map 'rss watch :handle :url :type',
  :action => 'watch_rss',
  :defaults => {:url => nil, :type => nil}
plugin.map 'rss unwatch :handle',
  :action => 'unwatch_rss'
plugin.map 'rss rmwatch :handle',
  :action => 'unwatch_rss'
plugin.map 'rss rewatch :handle',
  :action => 'rewatch_rss'
