#-- vim:sw=2:et
#++
#
# :title: RSS feed plugin for rbot
#
# Author:: Stanislav Karchebny <berkus@madfire.net>
# Author:: Ian Monroe <ian@monroe.nu>
# Author:: Mark Kretschmann <markey@web.de>
# Author:: Giuseppe Bilotta <giuseppe.bilotta@gmail.com>
#
# Copyright:: (C) 2004 Stanislav Karchebny
# Copyright:: (C) 2005 Ian Monroe, Mark Kretschmann
# Copyright:: (C) 2006-2007 Giuseppe Bilotta
#
# License:: MIT license

# require 'rss/parser'
# require 'rss/1.0'
# require 'rss/2.0'
# require 'rss/dublincore'
# # begin
# #   require 'rss/dublincore/2.0'
# # rescue
# #   warning "Unable to load RSS libraries, RSS plugin functionality crippled"
# # end
#
# GB: Let's just go for the simple stuff:
#
require 'rss'

class ::RssBlob
  attr_accessor :url
  attr_accessor :handle
  attr_accessor :type
  attr :watchers
  attr_accessor :refresh_rate
  attr_accessor :xml
  attr_accessor :title
  attr_accessor :items
  attr_accessor :mutex

  def initialize(url,handle=nil,type=nil,watchers=[], xml=nil)
    @url = url
    if handle
      @handle = handle
    else
      @handle = url
    end
    @type = type
    @watchers=[]
    @refresh_rate = nil
    @xml = xml
    @title = nil
    @items = nil
    @mutex = Mutex.new
    sanitize_watchers(watchers)
  end

  def dup
    @mutex.synchronize do
      self.class.new(@url,
                     @handle,
                     @type ? @type.dup : nil,
                     @watchers.dup,
                     @xml ? @xml.dup : nil)
    end
  end

  # Downcase all watchers, possibly turning them into Strings if they weren't
  def sanitize_watchers(list=@watchers)
    ls = list.dup
    @watchers.clear
    ls.each { |w|
      add_watch(w)
    }
  end

  def watched?
    !@watchers.empty?
  end

  def watched_by?(who)
    @watchers.include?(who.downcase)
  end

  def add_watch(who)
    if watched_by?(who)
      return nil
    end
    @mutex.synchronize do
      @watchers << who.downcase
    end
    return who
  end

  def rm_watch(who)
    @mutex.synchronize do
      @watchers.delete(who.downcase)
    end
  end

  def to_a
    [@handle,@url,@type,@refresh_rate,@watchers]
  end

  def to_s(watchers=false)
    if watchers
      a = self.to_a.flatten
    else
      a = self.to_a[0,3]
    end
    a.compact.join(" | ")
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
    :desc => "How many seconds to sleep before checking RSS feeds again")

  def initialize
    super
    if @registry.has_key?(:feeds)
      @feeds = @registry[:feeds]
      @feeds.keys.grep(/[A-Z]/) { |k|
        @feeds[k.downcase] = @feeds[k]
        @feeds.delete(k)
      }
      @feeds.each { |k, f|
        f.mutex = Mutex.new unless f.mutex
        f.sanitize_watchers
        parseRss(f) if f.xml
      }
    else
      @feeds = Hash.new
    end
    @watch = Hash.new
    rewatch_rss
  end

  def name
    "rss"
  end

  def watchlist
    @feeds.select { |h, f| f.watched? }
  end

  def cleanup
    stop_watches
  end

  def save
    unparsed = Hash.new()
    @feeds.each { |k, f|
      unparsed[k] = f.dup
    }
    @registry[:feeds] = unparsed
  end

  def stop_watch(handle)
    if @watch.has_key?(handle)
      begin
        debug "Stopping watch #{handle}"
        @bot.timer.remove(@watch[handle])
        @watch.delete(handle)
      rescue => e
        report_problem("Failed to stop watch for #{handle}", e, nil)
      end
    end
  end

  def stop_watches
    @watch.each_key { |k|
      stop_watch(k)
    }
  end

  def help(plugin,topic="")
    case topic
    when "show"
      "rss show #{Bold}handle#{Bold} [#{Bold}limit#{Bold}] : show #{Bold}limit#{Bold} (default: 5, max: 15) entries from rss #{Bold}handle#{Bold}; #{Bold}limit#{Bold} can also be in the form a..b, to display a specific range of items"
    when "list"
      "rss list [#{Bold}handle#{Bold}] : list all rss feeds (matching #{Bold}handle#{Bold})"
    when "watched"
      "rss watched [#{Bold}handle#{Bold}] [in #{Bold}chan#{Bold}]: list all watched rss feeds (matching #{Bold}handle#{Bold}) (in channel #{Bold}chan#{Bold})"
    when "who", "watches", "who watches"
      "rss who watches [#{Bold}handle#{Bold}]]: list all watchers for rss feeds (matching #{Bold}handle#{Bold})"
    when "add"
      "rss add #{Bold}handle#{Bold} #{Bold}url#{Bold} [#{Bold}type#{Bold}] : add a new rss called #{Bold}handle#{Bold} from url #{Bold}url#{Bold} (of type #{Bold}type#{Bold})"
    when "change"
      "rss change #{Bold}what#{Bold} of #{Bold}handle#{Bold} to #{Bold}new#{Bold} : change the #{Underline}handle#{Underline}, #{Underline}url#{Underline}, #{Underline}type#{Underline} or #{Underline}refresh#{Underline} rate of rss called #{Bold}handle#{Bold} to value #{Bold}new#{Bold}"
    when /^(del(ete)?|rm)$/
      "rss del(ete)|rm #{Bold}handle#{Bold} : delete rss feed #{Bold}handle#{Bold}"
    when "replace"
      "rss replace #{Bold}handle#{Bold} #{Bold}url#{Bold} [#{Bold}type#{Bold}] : try to replace the url of rss called #{Bold}handle#{Bold} with #{Bold}url#{Bold} (of type #{Bold}type#{Bold}); only works if nobody else is watching it"
    when "forcereplace"
      "rss forcereplace #{Bold}handle#{Bold} #{Bold}url#{Bold} [#{Bold}type#{Bold}] : replace the url of rss called #{Bold}handle#{Bold} with #{Bold}url#{Bold} (of type #{Bold}type#{Bold})"
    when "watch"
      "rss watch #{Bold}handle#{Bold} [#{Bold}url#{Bold} [#{Bold}type#{Bold}]]  [in #{Bold}chan#{Bold}]: watch rss #{Bold}handle#{Bold} for changes (in channel #{Bold}chan#{Bold}); when the other parameters are present, the feed will be created if it doesn't exist yet"
    when /(un|rm)watch/
      "rss unwatch|rmwatch #{Bold}handle#{Bold} [in #{Bold}chan#{Bold}]: stop watching rss #{Bold}handle#{Bold} (in channel #{Bold}chan#{Bold}) for changes"
    when "rewatch"
      "rss rewatch : restart threads that watch for changes in watched rss"
    else
      "manage RSS feeds: rss show|list|watched|add|change|del(ete)|rm|(force)replace|watch|unwatch|rmwatch|rewatch"
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
      ul = [[lims[1].to_i-1, 0].max, 14].min
      rev = false
    end

    feed = @feeds.fetch(handle.downcase, nil)
    unless feed
      m.reply "I don't know any feeds named #{handle}"
      return
    end

    m.reply "lemme fetch it..."
    title = items = nil
    fetched = fetchRss(feed, m)
    return unless fetched or feed.xml
    if not fetched and feed.items
      m.reply "using old data"
    else
      parsed = parseRss(feed, m)
      m.reply "using old data" unless parsed
    end
    return unless feed.items
    title = feed.title
    items = feed.items

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
    return item.pubDate if item.respond_to?(:pubDate) and item.pubDate
    return item.date if item.respond_to?(:date) and item.date
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
    @feeds.each { |handle, feed|
      next if wanted and !handle.match(/#{wanted}/i)
      reply << "#{feed.handle}: #{feed.url} (in format: #{feed.type ? feed.type : 'default'})"
      (reply << " refreshing every #{Utils.secs_to_string(feed.refresh_rate)}") if feed.refresh_rate
      (reply << " (watched)") if feed.watched_by?(m.replyto)
      reply << "\n"
    }
    if reply.empty?
      reply = "no feeds found"
      reply << " matching #{wanted}" if wanted
    end
    m.reply reply
  end

  def watched_rss(m, params)
    wanted = params[:handle]
    chan = params[:chan] || m.replyto
    reply = String.new
    watchlist.each { |handle, feed|
      next if wanted and !handle.match(/#{wanted}/i)
      next unless feed.watched_by?(chan)
      reply << "#{feed.handle}: #{feed.url} (in format: #{feed.type ? feed.type : 'default'})"
      (reply << " refreshing every #{Utils.secs_to_string(feed.refresh_rate)}") if feed.refresh_rate
      reply << "\n"
    }
    if reply.empty?
      reply = "no watched feeds"
      reply << " matching #{wanted}" if wanted
    end
    m.reply reply
  end

  def who_watches(m, params)
    wanted = params[:handle]
    reply = String.new
    watchlist.each { |handle, feed|
      next if wanted and !handle.match(/#{wanted}/i)
      reply << "#{feed.handle}: #{feed.url} (in format: #{feed.type ? feed.type : 'default'})"
      (reply << " refreshing every #{Utils.secs_to_string(feed.refresh_rate)}") if feed.refresh_rate
      reply << ": watched by #{feed.watchers.join(', ')}"
      reply << "\n"
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
    if @feeds.fetch(handle.downcase, nil) && !force
      m.reply "There is already a feed named #{handle} (URL: #{@feeds[handle.downcase].url})"
      return
    end
    unless url
      m.reply "You must specify both a handle and an url to add an RSS feed"
      return
    end
    @feeds[handle.downcase] = RssBlob.new(url,handle,type)
    reply = "Added RSS #{url} named #{handle}"
    if type
      reply << " (format: #{type})"
    end
    m.reply reply
    return handle
  end

  def change_rss(m, params)
    handle = params[:handle].downcase
    feed = @feeds.fetch(handle, nil)
    unless feed
      m.reply "No such feed with handle #{handle}"
      return
    end
    case params[:what].intern
    when :handle
      new = params[:new].downcase
      if @feeds.key?(new) and @feeds[new]
        m.reply "There already is a feed with handle #{new}"
        return
      else
        feed.mutex.synchronize do
          @feeds[new] = feed
          @feeds.delete(handle)
          feed.handle = new
        end
        handle = new
      end
    when :url
      new = params[:new]
      feed.mutex.synchronize do
        feed.url = new
      end
    when :format, :type
      new = params[:new]
      new = nil if new == 'default'
      feed.mutex.synchronize do
        feed.type = new
      end
    when :refresh
      new = params[:new].to_i
      new = nil if new == 0
      feed.mutex.synchronize do
        feed.refresh_rate = new
      end
    else
      m.reply "Don't know how to change #{params[:what]} for feeds"
      return
    end
    m.reply "Feed changed:"
    list_rss(m, {:handle => handle})
  end

  def del_rss(m, params, pass=false)
    feed = unwatch_rss(m, params, true)
    if feed.watched?
      m.reply "someone else is watching #{feed.handle}, I won't remove it from my list"
      return
    end
    @feeds.delete(feed.handle.downcase)
    m.okay unless pass
    return
  end

  def replace_rss(m, params)
    handle = params[:handle]
    if @feeds.key?(handle.downcase)
      del_rss(m, {:handle => handle}, true)
    end
    if @feeds.key?(handle.downcase)
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
    chan = params[:chan] || m.replyto
    url = params[:url]
    type = params[:type]
    if url
      add_rss(m, params)
    end
    feed = @feeds.fetch(handle.downcase, nil)
    if feed
      if feed.add_watch(chan)
        watchRss(feed, m)
        m.okay
      else
        m.reply "Already watching #{feed.handle} in #{chan}"
      end
    else
      m.reply "Couldn't watch feed #{handle} (no such feed found)"
    end
  end

  def unwatch_rss(m, params, pass=false)
    handle = params[:handle].downcase
    chan = params[:chan] || m.replyto
    unless @feeds.has_key?(handle)
      m.reply("dunno that feed")
      return
    end
    feed = @feeds[handle]
    if feed.rm_watch(chan)
      m.reply "#{chan} has been removed from the watchlist for #{feed.handle}"
    else
      m.reply("#{chan} wasn't watching #{feed.handle}") unless pass
    end
    if !feed.watched?
      stop_watch(handle)
    end
    return feed
  end

  def rewatch_rss(m=nil, params=nil)
    stop_watches

    # Read watches from list.
    watchlist.each{ |handle, feed|
      watchRss(feed, m)
    }
    m.okay if m
  end

  private
  def watchRss(feed, m=nil)
    if @watch.has_key?(feed.handle)
      report_problem("watcher thread for #{feed.handle} is already running", nil, m)
      return
    end
    status = Hash.new
    status[:failures] = 0
    @watch[feed.handle] = @bot.timer.add(0, status) {
      debug "watcher for #{feed} started"
      failures = status[:failures]
      begin
        debug "fetching #{feed}"
        oldxml = feed.xml ? feed.xml.dup : nil
        unless fetchRss(feed)
          failures += 1
        else
          if oldxml and oldxml == feed.xml
            debug "xml for #{feed} didn't change"
            failures -= 1 if failures > 0
          else
            if not feed.items
              debug "no previous items in feed #{feed}"
              parseRss(feed)
              failures -= 1 if failures > 0
            else
              otxt = feed.items.map { |item| item.to_s }
              unless parseRss(feed)
                debug "no items in feed #{feed}"
                failures += 1
              else
                debug "Checking if new items are available for #{feed}"
                failures -= 1 if failures > 0
                dispItems = feed.items.reject { |item|
                  otxt.include?(item.to_s)
                }
                if dispItems.length > 0
                  debug "Found #{dispItems.length} new items in #{feed}"
                  # When displaying watched feeds, publish them from older to newer
                  dispItems.reverse.each { |item|
                    printFormattedRss(feed, item)
                  }
                else
                  debug "No new items found in #{feed}"
                end
              end
            end
          end
        end
      rescue Exception => e
        error "Error watching #{feed}: #{e.inspect}"
        debug e.backtrace.join("\n")
        failures += 1
      end

      status[:failures] = failures

      feed.mutex.synchronize do
        seconds = (feed.refresh_rate || @bot.config['rss.thread_sleep']) * (failures + 1)
        seconds += seconds * (rand(100)-50)/100
        debug "watcher for #{feed} going to sleep #{seconds} seconds.."
        @bot.timer.reschedule(@watch[feed.handle], seconds)
      end
    }
    debug "watcher for #{feed} added"
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
    desc = item.description.gsub(/\s+/,' ').strip.riphtml if item.description
    link = item.link.chomp if item.link
    line1 = nil
    line2 = nil
    case feed.type
    when 'blog'
      line1 = "#{handle}#{date}#{item.category.content} blogged at #{link}"
      line2 = "#{handle}#{title} - #{desc}"
    when 'forum'
      line1 = "#{handle}#{date}#{title}#{' @ ' if item.title && item.link}#{link}"
    when 'wiki'
      line1 = "#{handle}#{date}#{title}#{' @ ' if item.title && item.link}#{link} has been edited by #{item.dc_creator}. #{desc}"
    when 'gmane'
      line1 = "#{handle}#{date}Message #{title} sent by #{item.dc_creator}. #{desc}"
    when 'trac'
      line1 = "#{handle}#{date}#{title} @ #{link}"
      unless item.title =~ /^Changeset \[(\d+)\]/
        line2 = "#{handle}#{date}#{desc}"
      end
    else
      line1 = "#{handle}#{date}#{title}#{' @ ' if item.title && item.link}#{link}"
    end
    places.each { |loc|
      @bot.say loc, line1, :overlong => :truncate
      next unless line2
      @bot.say loc, line2, :overlong => :truncate
    }
  end

  def fetchRss(feed, m=nil)
    begin
      # Use 60 sec timeout, cause the default is too low
      xml = @bot.httputil.get_cached(feed.url, 60, 60)
    rescue URI::InvalidURIError, URI::BadURIError => e
      report_problem("invalid rss feed #{feed.url}", e, m)
      return nil
    rescue => e
      report_problem("error getting #{feed.url}", e, m)
      return nil
    end
    debug "fetched #{feed}"
    unless xml
      report_problem("reading feed #{feed} failed", nil, m)
      return nil
    end
    # Ok, 0.9 feeds are not supported, maybe because
    # Netscape happily removed the DTD. So what we do is just to
    # reassign the 0.9 RDFs to 1.0, and hope it goes right.
    xml.gsub!("xmlns=\"http://my.netscape.com/rdf/simple/0.9/\"",
              "xmlns=\"http://purl.org/rss/1.0/\"")
    feed.mutex.synchronize do
      feed.xml = xml
    end
    return true
  end

  def parseRss(feed, m=nil)
    return nil unless feed.xml
    feed.mutex.synchronize do
      xml = feed.xml
      begin
        ## do validate parse
        rss = RSS::Parser.parse(xml)
        debug "parsed and validated #{feed}"
      rescue RSS::InvalidRSSError
        ## do non validate parse for invalid RSS 1.0
        begin
          rss = RSS::Parser.parse(xml, false)
          debug "parsed but not validated #{feed}"
        rescue RSS::Error => e
          report_problem("parsing rss stream failed, whoops =(", e, m)
          return nil
        end
      rescue RSS::Error => e
        report_problem("parsing rss stream failed, oioi", e, m)
        return nil
      rescue => e
        report_problem("processing error occured, sorry =(", e, m)
        return nil
      end
      items = []
      if rss.nil?
        report_problem("#{feed} does not include RSS 1.0 or 0.9x/2.0", nil, m)
      else
        begin
          rss.output_encoding = 'UTF-8'
        rescue RSS::UnknownConvertMethod => e
          report_problem("bah! something went wrong =(", e, m)
          return nil
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
        return nil
      end
      feed.title = title
      feed.items = items
      return true
    end
  end
end

plugin = RSSFeedsPlugin.new

plugin.map 'rss show :handle :limit',
  :action => 'show_rss',
  :requirements => {:limit => /^\d+(?:\.\.\d+)?$/},
  :defaults => {:limit => 5}
plugin.map 'rss list :handle',
  :action => 'list_rss',
  :defaults => {:handle => nil}
plugin.map 'rss watched :handle [in :chan]',
  :action => 'watched_rss',
  :defaults => {:handle => nil}
plugin.map 'rss who watches :handle',
  :action => 'who_watches',
  :defaults => {:handle => nil}
plugin.map 'rss add :handle :url :type',
  :action => 'add_rss',
  :defaults => {:type => nil}
plugin.map 'rss change :what of :handle to :new',
  :action => 'change_rss',
  :requirements => { :what => /handle|url|format|type|refresh/ }
plugin.map 'rss change :what for :handle to :new',
  :action => 'change_rss',
  :requirements => { :what => /handle|url|format|type|refesh/ }
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
plugin.map 'rss watch :handle :url :type [in :chan]',
  :action => 'watch_rss',
  :defaults => {:url => nil, :type => nil}
plugin.map 'rss unwatch :handle [in :chan]',
  :action => 'unwatch_rss'
plugin.map 'rss rmwatch :handle [in :chan]',
  :action => 'unwatch_rss'
plugin.map 'rss rewatch',
  :action => 'rewatch_rss'

