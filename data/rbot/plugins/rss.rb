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

  # Keep a 1:1 relation between commands and handlers
  @@handlers = {
    "rss" => "handle_rss",
    "addrss" => "handle_addrss",
    "rmrss" => "handle_rmrss",
    "rmwatch" => "handle_rmwatch",
    "listrss" => "handle_listrss",
    "listwatches" => "handle_listrsswatch",
    "rewatch" => "handle_rewatch",
    "watchrss" => "handle_watchrss",
  }

  def initialize
    super
    kill_threads
    if @registry.has_key?(:feeds)
      @feeds = @registry[:feeds]
    else
      @feeds = Hash.new
    end
    handle_rewatch
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
      # @@watchThreads.each { |url, thread|
      #   debug "Joining on killed thread for #{url}"
      #   thread.join
      # }
      @@watchThreads = Hash.new
    }
  end

  def help(plugin,topic="")
    "RSS Reader: rss name [limit] => read a named feed [limit maximum posts, default 5], addrss [force] name url => add a feed, listrss => list all available feeds, rmrss name => remove the named feed, watchrss url [type] => watch a rss feed for changes (type may be 'amarokblog', 'amarokforum', 'mediawiki', 'gmame' or empty - it defines special formatting of feed items), rewatch => restart all rss watches, rmwatch url => stop watching for changes in url, listwatches => see a list of watched feeds"
  end

  def report_problem(report, m=nil)
      if m
        m.reply report
      else
        warning report
      end
  end

  def privmsg(m)
    meth = self.method(@@handlers[m.plugin])
    meth.call(m)
  end

  def handle_rss(m)
    unless m.params
      m.reply("incorrect usage: " + help(m.plugin))
      return
    end
    limit = 5
    if m.params =~ /\s+(\d+)$/
      limit = $1.to_i
      if limit < 1 || limit > 15
        m.reply("weird, limit not in [1..15], reverting to default")
        limit = 5
      end
      m.params.gsub!(/\s+\d+$/, '')
    end

    url = ''
    if m.params =~ /^https?:\/\//
      url = m.params
      @@mutex.synchronize {
        @feeds[url] = RssBlob.new(url)
        feed = @feeds[url]
      }
    else
      feed = @feeds.fetch(m.params, nil)
      unless feed
        m.reply(m.params + "? what is that feed about?")
        return
      end
    end

    m.reply("Please wait, querying...")
    title = items = nil
    @@mutex.synchronize {
      title, items = fetchRss(feed, m)
    }
    return unless items
    m.reply("Channel : #{title}")
    # TODO: optional by-date sorting if dates present
    items[0...limit].each do |item|
      printRssItem(m.replyto,item)
    end
  end

  def handle_addrss(m)
    unless m.params
      m.reply "incorrect usage: " + help(m.plugin)
      return
    end
    if m.params =~ /^force /
      forced = true
      m.params.gsub!(/^force /, '')
    end
    feed = m.params.match(/^(\S+)\s+(\S+)$/)
    if feed.nil?
      m.reply("incorrect usage: " + help(m.plugin))
    end
    handle = feed[1]
    url = feed[2]
    debug "Handle: #{handle.inspect}, Url: #{url.inspect}"
    if @feeds.fetch(handle, nil) && !forced
      m.reply("But there is already a feed named #{handle} with url #{@feeds[handle].url}")
      return
    end
    handle.gsub!("|", '_')
    @@mutex.synchronize {
      @feeds[handle] = RssBlob.new(url,handle)
    }
    m.reply "RSS: Added #{url} with name #{handle}"
    return handle
  end

  def handle_rmrss(m)
    feed = handle_rmwatch(m, true)
    if feed.watched?
      m.reply "someone else is watching #{feed.handle}, I won't remove it from my list"
      return
    end
    @@mutex.synchronize {
      @feeds.delete(feed.handle)
    }
    m.okay
    return
  end

  def handle_rmwatch(m,pass=false)
    unless m.params
      m.reply "incorrect usage: " + help(m.plugin)
      return
    end
    handle = m.params
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

  def handle_listrss(m)
    reply = ''
    if @feeds.length == 0
      reply = "No feeds yet."
    else
      @@mutex.synchronize {
        @feeds.each { |handle, feed|
          reply << "#{feed.handle}: #{feed.url} (in format: #{feed.type ? feed.type : 'default'})"
          (reply << " (watched)") if feed.watched_by?(m.replyto)
          reply << "\n"
          debug reply
        }
      }
    end
    m.reply reply
  end

  def handle_listrsswatch(m)
    reply = ''
    if watchlist.length == 0
      reply = "No watched feeds yet."
    else
      watchlist.each { |handle, feed|
        (reply << "#{feed.handle}: #{feed.url} (in format: #{feed.type ? feed.type : 'default'})\n") if feed.watched_by?(m.replyto)
        debug reply
      }
    end
    m.reply reply
  end

  def handle_rewatch(m=nil)
    kill_threads

    # Read watches from list.
    watchlist.each{ |handle, feed|
      watchRss(feed, m)
    }
    m.okay if m
  end

  def handle_watchrss(m)
    unless m.params
      m.reply "incorrect usage: " + help(m.plugin)
      return
    end
    if m.params =~ /\s+/
      handle = handle_addrss(m)
    else
      handle = m.params
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
            dispItems = newItems.reject { |item|
              oldItems.include?(item)
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
          oldItems = newItems
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
        printRSSItem(loc,item)
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
plugin.register("rss")
plugin.register("addrss")
plugin.register("rmrss")
plugin.register("rmwatch")
plugin.register("listrss")
plugin.register("rewatch")
plugin.register("watchrss")
plugin.register("listwatches")

