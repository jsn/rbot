require 'uri'

Url = Struct.new("Url", :channel, :nick, :time, :url)
TITLE_RE = /<\s*?title\s*?>(.+?)<\s*?\/title\s*?>/im

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

  def initialize
    super
    @registry.set_default(Array.new)
  end

  def help(plugin, topic="")
    "urls [<max>=4] => list <max> last urls mentioned in current channel, urls search [<max>=4] <regexp> => search for matching urls. In a private message, you must specify the channel to query, eg. urls <channel> [max], urls search <channel> [max] <regexp>"
  end

  def get_title_from_html(pagedata)
    return unless TITLE_RE.match(pagedata)
    title = $1.strip.gsub(/\s*\n+\s*/, " ")
    title = Utils.decode_html_entities title
    title = title[0..255] if title.length > 255
    "[Link Info] title: #{title}"
  end

  def read_data_from_response(response, amount)

    amount_read = 0
    chunks = []

    response.read_body do |chunk|   # read body now

      amount_read += chunk.length

      # if amount_read > amount
      #   amount_of_overflow = amount_read - amount
      #   chunk = chunk[0...-amount_of_overflow]
      # end

      chunks << chunk

      break if amount_read >= amount

    end

    chunks.join('')

  end

  def get_title_for_url(uri_str, depth=@bot.config['http.max_redir'])
    # This god-awful mess is what the ruby http library has reduced me to.
    # Python's HTTP lib is so much nicer. :~(

    if depth == 0
        raise "Error: Maximum redirects hit."
    end

    debug "+ Getting #{uri_str.to_s}"
    url = uri_str.kind_of?(URI) ? uri_str : URI.parse(uri_str)
    return if url.scheme !~ /https?/

    title = nil

    debug "+ connecting to #{url.host}:#{url.port}"
    http = @bot.httputil.get_proxy(url)
    http.start { |http|

      http.request_get(url.request_uri(), @bot.httputil.headers) { |response|

        case response
          when Net::HTTPRedirection
            # call self recursively if this is a redirect
            redirect_to = response['location']  || '/'
            debug "+ redirect location: #{redirect_to.inspect}"
            url = URI.join(url.to_s, redirect_to)
            debug "+ whee, redirecting to #{url.to_s}!"
            return get_title_for_url(url, depth-1)
          when Net::HTTPSuccess
            if response['content-type'] =~ /^text\//
              # since the content is 'text/*' and is small enough to
              # be a webpage, retrieve the title from the page
              debug "+ getting #{url.request_uri}"
              # was 5*10^4 ... seems to much to me ... 4k should be enough for everybody ;)
              data = read_data_from_response(response, 4096)
              return get_title_from_html(data)
            else
              unless @bot.config['url.titles_only']
                # content doesn't have title, just display info.
                size = response['content-length'].gsub(/(\d)(?=\d{3}+(?:\.|$))(\d{3}\..*)?/,'\1,\2')
                size = size ? ", size: #{size} bytes" : ""
                return "[Link Info] type: #{response['content-type']}#{size}"
              end
            end
          else
            return "[Link Info] Error getting link (#{response.code} - #{response.message})"
          end # end of "case response"

      } # end of request block
    } # end of http start block

    return title

  rescue SocketError => e
    return "[Link Info] Error connecting to site (#{e.message})"
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
          debug "Getting title for #{urlstr}..."
          begin
          title = get_title_for_url urlstr
          if title
            m.reply title
            debug "Title found!"
          else
            debug "Title not found!"
          end
          rescue => e
            debug "Failed: #{e}"
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
