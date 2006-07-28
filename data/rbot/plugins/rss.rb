# RSS feed plugin for RubyBot
# (c) 2004 Stanislav Karchebny <berkus@madfire.net>
# (c) 2005 Ian Monroe <ian@monroe.nu>
# (c) 2005 Mark Kretschmann <markey@web.de>
# Licensed under MIT License.

require 'rss/parser'
require 'rss/1.0'
require 'rss/2.0'
require 'rss/dublincore'
# begin
#   require 'rss/dublincore/2.0'
# rescue
#   warning "Unable to load RSS libraries, RSS plugin functionality crippled"
# end

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

  def to_a
    [@handle,@url,@type,@watchers]
  end

  def to_s(watchers=false)
    if watchers
      a = self.to_a.flatten
    else
      a = self.to_a[0,3]
    end
    a.join(" | ")
  end
end

class RSSFeedsPlugin < Plugin
  BotConfig.register BotConfigIntegerValue.new('rss.head_max',
    :default => 30, :validate => Proc.new{|v| v > 0 && v < 200},
    :desc => "How many characters to use of a RSS item header")

  BotConfig.register BotConfigIntegerValue.new('rss.text_max',
    :default => 90, :validate => Proc.new{|v| v > 0 && v < 400},
    :desc => "How many characters to use of a RSS item text")

  BotConfig.register BotConfigIntegerValue.new('rss.thread_sleep',
    :default => 300, :validate => Proc.new{|v| v > 30},
    :desc => "How many characters to use of a RSS item text")

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
      "rss show #{Bold}handle#{Bold} [#{Bold}limit#{Bold}] : show #{Bold}limit#{Bold} (default: 5, max: 15) entries from rss #{Bold}handle#{Bold}; #{Bold}limit#{Bold} can also be in the form a..b, to display a specific range of items"
    when "list"
      "rss list [#{Bold}handle#{Bold}] : list all rss feeds (matching #{Bold}handle#{Bold})"
    when "watched"
      "rss watched [#{Bold}handle#{Bold}] : list all watched rss feeds (matching #{Bold}handle#{Bold})"
    when "add"
      "rss add #{Bold}handle#{Bold} #{Bold}url#{Bold} [#{Bold}type#{Bold}] : add a new rss called #{Bold}handle#{Bold} from url #{Bold}url#{Bold} (of type #{Bold}type#{Bold})"
    when /^(del(ete)?|rm)$/
      "rss del(ete)|rm #{Bold}handle#{Bold} : delete rss feed #{Bold}handle#{Bold}"
    when "replace"
      "rss replace #{Bold}handle#{Bold} #{Bold}url#{Bold} [#{Bold}type#{Bold}] : try to replace the url of rss called #{Bold}handle#{Bold} with #{Bold}url#{Bold} (of type #{Bold}type#{Bold}); only works if nobody else is watching it"
    when "forcereplace"
      "rss forcereplace #{Bold}handle#{Bold} #{Bold}url#{Bold} [#{Bold}type#{Bold}] : replace the url of rss called #{Bold}handle#{Bold} with #{Bold}url#{Bold} (of type #{Bold}type#{Bold})"
    when "watch"
      "rss watch #{Bold}handle#{Bold} [#{Bold}url#{Bold} [#{Bold}type#{Bold}]] : watch rss #{Bold}handle#{Bold} for changes; when the other parameters are present, it will be created if it doesn't exist yet"
    when /(un|rm)watch/
      "rss unwatch|rmwatch #{Bold}handle#{Bold} : stop watching rss #{Bold}handle#{Bold} for changes"
    when "rewatch"
      "rss rewatch : restart threads that watch for changes in watched rss"
    else
      "manage RSS feeds: rss show|list|watched|add|del(ete)|rm|(force)replace|watch|unwatch|rmwatch|rewatch"
    end
  end

  def report_problem(report, e=nil, m=nil)
    if m && m.respond_to?(:reply)
      m.reply report
    else
      warning report
    end
    if e
      debug e.inspect
      debug e.backtrace.join("\n") if e.respond_to?(:backtrace)
    end
  end

  def show_rss(m, params)
    handle = params[:handle]
    lims = params[:limit].to_s.match(/(\d+)(?:..(\d+))?/)
    debug lims.to_a.inspect
    if lims[2]
      ll = [[lims[1].to_i-1,lims[2].to_i-1].min,  0].max
      ul = [[lims[1].to_i-1,lims[2].to_i-1].max, 14].min
      rev = lims[1].to_i > lims[2].to_i
    else
      ll = 0
      ul = [[lims[1].to_i-1, 1].max, 14].min
      rev = false
    end

    feed = @feeds.fetch(handle, nil)
    unless feed
      m.reply "I don't know any feeds named #{handle}"
      return
    end

    m.reply "lemme fetch it..."
    title = items = nil
    @@mutex.synchronize {
      title, items = fetchRss(feed, m)
    }
    return unless items

    # We sort the feeds in freshness order (newer ones first)
    items = freshness_sort(items)
    disp = items[ll..ul]
    disp.reverse! if rev

    m.reply "Channel : #{title}"
    disp.each do |item|
      printFormattedRss(feed, item, {:places=>[m.replyto],:handle=>nil,:date=>true})
    end
  end

  def itemDate(item,ex=nil)
    return item.pubDate if item.respond_to?(:pubDate)
    return item.date if item.respond_to?(:date)
    return ex
  end

  def freshness_sort(items)
    notime = Time.at(0)
    items.sort { |a, b|
      itemDate(b, notime) <=> itemDate(a, notime)
    }
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
    unless url.match(/https?/)
      m.reply "I only deal with feeds from HTTP sources, so I can't use #{url} (maybe you forgot the handle?)"
      return
    end
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
      report_problem("watcher thread for #{feed.handle} is already running", nil, m)
      return
    end
    @@watchThreads[feed.handle] = Thread.new do
      debug "watcher for #{feed} started"
      oldItems = []
      firstRun = true
      failures = 0
      loop do
        begin
          debug "fetching #{feed}"
          title = newItems = nil
          @@mutex.synchronize {
            title, newItems = fetchRss(feed)
          }
          unless newItems
            debug "no items in feed #{feed}"
            failures +=1
          else
            debug "Checking if new items are available for #{feed}"
            if firstRun
              debug "First run, we'll see next time"
              firstRun = false
            else
              otxt = oldItems.map { |item| item.to_s }
              dispItems = newItems.reject { |item|
                otxt.include?(item.to_s)
              }
              if dispItems.length > 0
                debug "Found #{dispItems.length} new items in #{feed}"
                dispItems.each { |item|
                  @@mutex.synchronize {
                    printFormattedRss(feed, item)
                  }
                }
              else
                debug "No new items found in #{feed}"
              end
            end
            oldItems = newItems.dup
          end
        rescue Exception => e
          error "Error watching #{feed}: #{e.inspect}"
          debug e.backtrace.join("\n")
          failures += 1
        end

        seconds = @bot.config['rss.thread_sleep'] * (failures + 1)
        seconds += seconds * (rand(100)-50)/100
        debug "watcher for #{feed} going to sleep #{seconds} seconds.."
        sleep seconds
      end
    end
  end

  def printFormattedRss(feed, item, opts=nil)
    places = feed.watchers
    handle = "::#{feed.handle}:: "
    date = String.new
    if opts
      places = opts[:places] if opts.key?(:places)
      handle = opts[:handle].to_s if opts.key?(:handle)
      if opts.key?(:date) && opts[:date]
        if item.respond_to?(:pubDate) 
          if item.pubDate.class <= Time
            date = item.pubDate.strftime("%Y/%m/%d %H.%M.%S")
          else
            date = item.pubDate.to_s
          end
        elsif  item.respond_to?(:date)
          if item.date.class <= Time
            date = item.date.strftime("%Y/%m/%d %H.%M.%S")
          else
            date = item.date.to_s
          end
        else
          date = "(no date)"
        end
        date += " :: "
      end
    end
    title = "#{Bold}#{item.title.chomp.riphtml}#{Bold}" if item.title
    desc = item.description.gsub(/\s+/,' ').strip.riphtml.shorten(@bot.config['rss.text_max']) if item.description
    link = item.link.chomp if item.link
    places.each { |loc|
      case feed.type
      when 'blog'
        @bot.say loc, "#{handle}#{date}#{item.category.content} blogged at #{link}"
        @bot.say loc, "#{handle}#{title} - #{desc}"
      when 'forum'
        @bot.say loc, "#{handle}#{date}#{title}#{' @ ' if item.title && item.link}#{link}"
      when 'wiki'
        @bot.say loc, "#{handle}#{date}#{item.title} has been edited by #{item.dc_creator}. #{desc} #{link}"
      when 'gmame'
        @bot.say loc, "#{handle}#{date}Message #{title} sent by #{item.dc_creator}. #{desc}"
      when 'trac'
        @bot.say loc, "#{handle}#{date}#{title} @ #{link}"
        unless item.title =~ /^Changeset \[(\d+)\]/
          @bot.say loc, "#{handle}#{date}#{desc}"
        end
      else
        @bot.say loc, "#{handle}#{date}#{title}#{' @ ' if item.title && item.link}#{link}"
      end
    }
  end

  def fetchRss(feed, m=nil)
    begin
      # Use 60 sec timeout, cause the default is too low
      # Do not use get_cached for RSS until we have proper cache handling
      # xml = @bot.httputil.get_cached(feed.url,60,60)
      xml = @bot.httputil.get(feed.url,60,60)
    rescue URI::InvalidURIError, URI::BadURIError => e
      report_problem("invalid rss feed #{feed.url}", e, m)
      return
    rescue => e
      report_problem("error getting #{feed.url}", e, m)
      return
    end
    debug "fetched #{feed}"
    unless xml
      report_problem("reading feed #{feed} failed", nil, m)
      return
    end

    begin
      ## do validate parse
      rss = RSS::Parser.parse(xml)
      debug "parsed #{feed}"
    rescue RSS::InvalidRSSError
      ## do non validate parse for invalid RSS 1.0
      begin
        rss = RSS::Parser.parse(xml, false)
      rescue RSS::Error => e
        report_problem("parsing rss stream failed, whoops =(", e, m)
        return
      end
    rescue RSS::Error => e
      report_problem("parsing rss stream failed, oioi", e, m)
      return
    rescue => e
      report_problem("processing error occured, sorry =(", e, m)
      return
    end
    items = []
    if rss.nil?
      report_problem("#{feed} does not include RSS 1.0 or 0.9x/2.0", nil, m)
    else
      begin
        rss.output_encoding = 'UTF-8'
      rescue RSS::UnknownConvertMethod => e
        report_problem("bah! something went wrong =(", e, m)
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
      report_problem("no items found in the feed, maybe try weed?", e, m)
      return
    end
    return [title, items]
  end
end

plugin = RSSFeedsPlugin.new

plugin.map 'rss show :handle :limit',
  :action => 'show_rss',
  :requirements => {:limit => /^\d+(?:\.\.\d+)?$/},
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

