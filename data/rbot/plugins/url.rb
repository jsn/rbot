require 'uri'

Url = Struct.new("Url", :channel, :nick, :time, :url)
TITLE_RE = /<\s*?title\s*?>(.+?)<\s*?\/title\s*?>/im
LINK_INFO = "[Link Info]"

class UrlPlugin < Plugin
  BotConfig.register BotConfigIntegerValue.new('url.max_urls',
    :default => 100, :validate => Proc.new{|v| v > 0},
    :desc => "Maximum number of urls to store. New urls replace oldest ones.")
  BotConfig.register BotConfigBooleanValue.new('url.display_link_info',
    :default => false,
    :desc => "Get the title of any links pasted to the channel and display it (also tells if the link is broken or the site is down)")
  BotConfig.register BotConfigBooleanValue.new('url.titles_only',
    :default => false,
    :desc => "Only show info for links that have <title> tags (in other words, don't display info for jpegs, mpegs, etc.)")
  BotConfig.register BotConfigBooleanValue.new('url.first_par',
    :default => false,
    :desc => "Also try to get the first paragraph of a web page")

  def initialize
    super
    @registry.set_default(Array.new)
  end

  def help(plugin, topic="")
    "urls [<max>=4] => list <max> last urls mentioned in current channel, urls search [<max>=4] <regexp> => search for matching urls. In a private message, you must specify the channel to query, eg. urls <channel> [max], urls search <channel> [max] <regexp>"
  end

  def get_title_from_html(pagedata)
    return unless TITLE_RE.match(pagedata)
    $1.ircify_html
  end

  def get_title_for_url(uri_str)

    url = uri_str.kind_of?(URI) ? uri_str : URI.parse(uri_str)
    return if url.scheme !~ /https?/

    title = nil

    begin
      range = @bot.config['http.info_bytes']
      response = @bot.httputil.get_response(url, :range => "bytes=0-#{range}")
      if response.code != "206" && response.code != "200"
        return "Error getting link (#{response.code} - #{response.message})"
      end
      extra = String.new

      if response['content-type'] =~ /^text\//

        body = response.body.slice(0, range)
        title = String.new

        # since the content is 'text/*' and is small enough to
        # be a webpage, retrieve the title from the page
        debug "+ getting #{url.request_uri}"

        # we act differently depending on whether we want the first par or not:
        # in the first case we download the initial part and the parse it; in the second
        # case we only download as much as we need to find the title
        if @bot.config['url.first_par']
          title = get_title_from_html(body)
          first_par = Utils.ircify_first_html_par(body, :strip => title)
          extra << "\n#{LINK_INFO} text: #{first_par}" unless first_par.empty?
          return "title: #{title}#{extra}" if title
        else
          title = get_title_from_html(body)
          return "title: #{title}" if title
        end

        # if nothing was found, provide more basic info
      end

      debug response.to_hash.inspect
      unless @bot.config['url.titles_only']
        # content doesn't have title, just display info.
        size = response['content-length'].gsub(/(\d)(?=\d{3}+(?:\.|$))(\d{3}\..*)?/,'\1,\2') rescue nil
        size = size ? ", size: #{size} bytes" : ""
        return "type: #{response['content-type']}#{size}#{extra}"
      end
    rescue Exception => e
      error e.inspect
      debug e.backtrace.join("\n")
      return "Error connecting to site (#{e.message})"
    end
  end

  def listen(m)
    return unless m.kind_of?(PrivMessage)
    return if m.address?
    # TODO support multiple urls in one line
    if m.message =~ /(f|ht)tps?:\/\//
      if m.message =~ /((f|ht)tps?:\/\/.*?)(?:\s+|$)/
        urlstr = $1
        list = @registry[m.target]

        if @bot.config['url.display_link_info']
          Thread.start do
            debug "Getting title for #{urlstr}..."
            begin
              title = get_title_for_url urlstr
              if title
                m.reply "#{LINK_INFO} #{title}", :overlong => :truncate
                debug "Title found!"
              else
                debug "Title not found!"
              end
            rescue => e
              debug "Failed: #{e}"
            end
          end
        end

        # check to see if this url is already listed
        return if list.find {|u| u.url == urlstr }

        url = Url.new(m.target, m.sourcenick, Time.new, urlstr)
        debug "#{list.length} urls so far"
        if list.length > @bot.config['url.max_urls']
          list.pop
        end
        debug "storing url #{url.url}"
        list.unshift url
        debug "#{list.length} urls now"
        @registry[m.target] = list
      end
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
      list[0..(max-1)].each do |url|
        m.reply "[#{url.time.strftime('%Y/%m/%d %H:%M:%S')}] <#{url.nick}> #{url.url}"
      end
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
      regex.match(url.url) || regex.match(url.nick)
    }
    if list.empty?
      m.reply "no matches for channel #{channel}"
    else
      list[0..(max-1)].each do |url|
        m.reply "[#{url.time.strftime('%Y/%m/%d %H:%M:%S')}] <#{url.nick}> #{url.url}"
      end
    end
  end
end
plugin = UrlPlugin.new
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
