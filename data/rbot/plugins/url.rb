#-- vim:sw=2:et
#++
#
# :title: Url plugin

define_structure :Url, :channel, :nick, :time, :url, :info

class ::UrlLinkError < RuntimeError
end

class UrlPlugin < Plugin
  LINK_INFO = "[Link Info]"
  OUR_UNSAFE = Regexp.new("[^#{URI::PATTERN::UNRESERVED}#{URI::PATTERN::RESERVED}%# ]", false, 'N')

  Config.register Config::IntegerValue.new('url.max_urls',
    :default => 100, :validate => Proc.new{|v| v > 0},
    :desc => "Maximum number of urls to store. New urls replace oldest ones.")
  Config.register Config::IntegerValue.new('url.display_link_info',
    :default => 0,
    :desc => "Get the title of links pasted to the channel and display it (also tells if the link is broken or the site is down). Do it for at most this many links per line (set to 0 to disable)")
  Config.register Config::BooleanValue.new('url.titles_only',
    :default => false,
    :desc => "Only show info for links that have <title> tags (in other words, don't display info for jpegs, mpegs, etc.)")
  Config.register Config::BooleanValue.new('url.first_par',
    :default => false,
    :desc => "Also try to get the first paragraph of a web page")
  Config.register Config::BooleanValue.new('url.info_on_list',
    :default => false,
    :desc => "Show link info when listing/searching for urls")
  Config.register Config::ArrayValue.new('url.no_info_hosts',
    :default => ['localhost', '^192\.168\.', '^10\.', '^127\.', '^172\.(1[6-9]|2\d|31)\.'],
    :on_change => Proc.new { |bot, v| bot.plugins['url'].reset_no_info_hosts },
    :desc => "A list of regular expressions matching hosts for which no info should be provided")


  def initialize
    super
    @registry.set_default(Array.new)
    unless @bot.config['url.display_link_info'].kind_of?(Integer)
      @bot.config.items[:'url.display_link_info'].set_string(@bot.config['url.display_link_info'].to_s)
    end
    reset_no_info_hosts
  end

  def reset_no_info_hosts
    @no_info_hosts = Regexp.new(@bot.config['url.no_info_hosts'].join('|'), true)
    debug "no info hosts regexp set to #{@no_info_hosts}"
  end

  def help(plugin, topic="")
    "url info <url> => display link info for <url> (set url.display_link_info > 0 if you want the bot to do it automatically when someone writes an url), urls [<max>=4] => list <max> last urls mentioned in current channel, urls search [<max>=4] <regexp> => search for matching urls. In a private message, you must specify the channel to query, eg. urls <channel> [max], urls search <channel> [max] <regexp>"
  end

  def get_title_from_html(pagedata)
    return pagedata.ircify_html_title
  end

  def get_title_for_url(uri_str, opts = {})

    url = uri_str.kind_of?(URI) ? uri_str : URI.parse(uri_str)
    return if url.scheme !~ /https?/

    if url.host =~ @no_info_hosts
      return "Sorry, info retrieval for #{url.host} is disabled"
    end

    logopts = opts.dup

    title = nil
    extra = String.new

    begin
      debug "+ getting #{url.request_uri}"
      @bot.httputil.get_response(url) { |resp|
        case resp
        when Net::HTTPSuccess

          debug resp.to_hash

          if resp['content-type'] =~ /^text\/|(?:x|ht)ml/
            # The page is text or HTML, so we can try finding a title and, if
            # requested, the first par.
            #
            # We act differently depending on whether we want the first par or
            # not: in the first case we download the initial part and the parse
            # it; in the second case we only download as much as we need to find
            # the title
            #
            if @bot.config['url.first_par']
              partial = resp.partial_body(@bot.config['http.info_bytes'])
              logopts[:title] = title = get_title_from_html(partial)
              if url.fragment and not url.fragment.empty?
                fragreg = /.*?<a\s+[^>]*name=["']?#{url.fragment}["']?.*?>/im
                partial.sub!(fragreg,'')
              end
              first_par = Utils.ircify_first_html_par(partial, :strip => title)
              unless first_par.empty?
                logopts[:extra] = first_par
                extra << ", #{Bold}text#{Bold}: #{first_par}"
              end
              call_event(:url_added, url.to_s, logopts)
              return "#{Bold}title#{Bold}: #{title}#{extra}" if title
            else
              resp.partial_body(@bot.config['http.info_bytes']) { |part|
                logopts[:title] = title = get_title_from_html(part)
                call_event(:url_added, url.to_s, logopts)
                return "#{Bold}title#{Bold}: #{title}" if title
              }
            end
          # if nothing was found, provide more basic info, as for non-html pages
          else
            resp.no_cache = true
          end

          enc = resp['content-encoding']
          logopts[:extra] = String.new
          logopts[:extra] << "Content Type: #{resp['content-type']}"
          if enc
            logopts[:extra] << ", encoding: #{enc}"
            extra << ", #{Bold}encoding#{Bold}: #{enc}"
          end

          unless @bot.config['url.titles_only']
            # content doesn't have title, just display info.
            size = resp['content-length'].gsub(/(\d)(?=\d{3}+(?:\.|$))(\d{3}\..*)?/,'\1,\2') rescue nil
            if size
              logopts[:extra] << ", size: #{size} bytes"
              size = ", #{Bold}size#{Bold}: #{size} bytes"
            end
            call_event(:url_added, url.to_s, logopts)
            return "#{Bold}type#{Bold}: #{resp['content-type']}#{size}#{extra}"
          end
          call_event(:url_added, url.to_s, logopts)
        else
          raise UrlLinkError, "getting link (#{resp.code} - #{resp.message})"
        end
      }
      return nil
    rescue Exception => e
      case e
      when UrlLinkError
        raise e
      else
        error e
        raise "connecting to site/processing information (#{e.message})"
      end
    end
  end

  def handle_urls(m, urls, display_info=@bot.config['url.display_link_info'])
    return if urls.empty?
    debug "found urls #{urls.inspect}"
    list = m.public? ? @registry[m.target] : nil
    debug "display link info: #{display_info}"
    urls_displayed = 0
    urls.each do |urlstr|
      debug "working on #{urlstr}"
      next unless urlstr =~ /^https?:/
      title = nil
      debug "Getting title for #{urlstr}..."
      begin
        title = get_title_for_url(urlstr,
                                  :nick => m.source.nick,
                                  :channel => m.channel,
                                  :ircline => m.message)
        debug "Title #{title ? '' : 'not '} found"
      rescue => e
        m.reply "Error #{e.message}"
      end

      if display_info > urls_displayed
        if title
          m.reply("#{LINK_INFO} #{title}", :overlong => :truncate)
          urls_displayed += 1
        end
      end

      next unless list

      # check to see if this url is already listed
      next if list.find {|u| u.url == urlstr }

      url = Url.new(m.target, m.sourcenick, Time.new, urlstr, title)
      debug "#{list.length} urls so far"
      list.pop if list.length > @bot.config['url.max_urls']
      debug "storing url #{url.url}"
      list.unshift url
      debug "#{list.length} urls now"
    end
    @registry[m.target] = list
  end

  def info(m, params)
    escaped = URI.escape(params[:urls].to_s, OUR_UNSAFE)
    urls = URI.extract(escaped)
    Thread.new { handle_urls(m, urls, params[:urls].length) }
  end

  def listen(m)
    return unless m.kind_of?(PrivMessage)
    return if m.address?

    escaped = URI.escape(m.message, OUR_UNSAFE)
    urls = URI.extract(escaped)
    Thread.new { handle_urls(m, urls) }
  end

  def reply_urls(opts={})
    list = opts[:list]
    max = opts[:max]
    channel = opts[:channel]
    m = opts[:msg]
    return unless list and max and m
    list[0..(max-1)].each do |url|
      disp = "[#{url.time.strftime('%Y/%m/%d %H:%M:%S')}] <#{url.nick}> #{url.url}"
      if @bot.config['url.info_on_list']
        title = url.info ||
          get_title_for_url(url.url,
                            :nick => url.nick, :channel => channel) rescue nil
        # If the url info was missing and we now have some, try to upgrade it
        if channel and title and not url.info
          ll = @registry[channel]
          debug ll
          if el = ll.find { |u| u.url == url.url }
            el.info = title
            @registry[channel] = ll
          end
        end
        disp << " --> #{title}" if title
      end
      m.reply disp, :overlong => :truncate
    end
  end

  def urls(m, params)
    channel = params[:channel] ? params[:channel] : m.target
    max = params[:limit].to_i
    max = 10 if max > 10
    max = 1 if max < 1
    list = @registry[channel]
    if list.empty?
      m.reply "no urls seen yet for channel #{channel}"
    else
      reply_urls :msg => m, :channel => channel, :list => list, :max => max
    end
  end

  def search(m, params)
    channel = params[:channel] ? params[:channel] : m.target
    max = params[:limit].to_i
    string = params[:string]
    max = 10 if max > 10
    max = 1 if max < 1
    regex = Regexp.new(string, Regexp::IGNORECASE)
    list = @registry[channel].find_all {|url|
      regex.match(url.url) || regex.match(url.nick) ||
        (@bot.config['url.info_on_list'] && regex.match(url.info))
    }
    if list.empty?
      m.reply "no matches for channel #{channel}"
    else
      reply_urls :msg => m, :channel => channel, :list => list, :max => max
    end
  end
end

plugin = UrlPlugin.new
plugin.map 'urls info *urls', :action => 'info'
plugin.map 'url info *urls', :action => 'info'
plugin.map 'urls search :channel :limit :string', :action => 'search',
                          :defaults => {:limit => 4},
                          :requirements => {:limit => /^\d+$/},
                          :public => false
plugin.map 'urls search :limit :string', :action => 'search',
                          :defaults => {:limit => 4},
                          :requirements => {:limit => /^\d+$/},
                          :private => false
plugin.map 'urls :channel :limit', :defaults => {:limit => 4},
                          :requirements => {:limit => /^\d+$/},
                          :public => false
plugin.map 'urls :limit', :defaults => {:limit => 4},
                          :requirements => {:limit => /^\d+$/},
                          :private => false
