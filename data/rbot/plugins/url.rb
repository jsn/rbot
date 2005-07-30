Url = Struct.new("Url", :channel, :nick, :time, :url)

class UrlPlugin < Plugin
  BotConfig.register BotConfigIntegerValue.new('url.max_urls',
    :default => 100, :validate => Proc.new{|v| v > 0},
    :desc => "Maximum number of urls to store. New urls replace oldest ones.")
  
  def initialize
    super
    @registry.set_default(Array.new)
  end
  def help(plugin, topic="")
    "urls [<max>=4] => list <max> last urls mentioned in current channel, urls search [<max>=4] <regexp> => search for matching urls. In a private message, you must specify the channel to query, eg. urls <channel> [max], urls search <channel> [max] <regexp>"
  end
  def listen(m)
    return unless m.kind_of?(PrivMessage)
    return if m.address?
    # TODO support multiple urls in one line
    if m.message =~ /(f|ht)tps?:\/\//
      if m.message =~ /((f|ht)tps?:\/\/.*?)(?:\s+|$)/
        urlstr = $1
        list = @registry[m.target]
        # check to see if this url is already listed
        return if list.find {|u|
          u.url == urlstr
        }
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
    regex = Regexp.new(string)
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
