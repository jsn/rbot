Url = Struct.new("Url", :channel, :nick, :time, :url)

class UrlPlugin < Plugin
  def initialize
    super
    @registry.set_default(Array.new)
  end
  def help(plugin, topic="")
    "urls [<max>=4] => list <max> last urls mentioned in current channel, urls <channel> [<max>=4] => list <max> last urls mentioned in <channel>, urls search <regexp> => search for matching urls, urls search <channel> <regexp>, search for matching urls in channel <channel>"
  end
  def listen(m)
    return unless m.kind_of?(PrivMessage)
    return if m.address?
    # TODO support multiple urls in one line
    if m.message =~ /(f|ht)tp:\/\//
      if m.message =~ /((f|ht)tp:\/\/.*?)(?:\s+|$)/
        url = Url.new(m.target, m.sourcenick, Time.new, $1)
        list = @registry[m.target]
        debug "#{list.length} urls so far"
        if list.length > 50
          list.pop
        end
        debug "storing url #{url.url}"
        list.unshift url
        debug "#{list.length} urls now"
        @registry[m.target] = list
      end
    end
  end
  def privmsg(m)
    case m.params
    when nil
      if m.public?
        urls m, m.target
      else
        m.reply "in a private message, you need to specify a channel name for urls"
      end
    when (/^(\d+)$/)
      max = $1.to_i
      if m.public?
        urls m, m.target, max
      else
        m.reply "in a private message, you need to specify a channel name for urls"
      end
    when (/^(#.*?)\s+(\d+)$/)
      channel = $1
      max = $2.to_i
      urls m, channel, max
    when (/^(#.*?)$/)
      channel = $1
      urls m, channel
    when (/^search\s+(#.*?)\s+(.*)$/)
      channel = $1
      string = $2
      search m, channel, string
    when (/^search\s+(.*)$/)
      string = $1
      if m.public?
        search m, m.target, string
      else
        m.reply "in a private message, you need to specify a channel name for urls"
      end
    else
      m.reply "incorrect usage: " + help(m.plugin)
    end
  end

  def urls(m, channel, max=4)
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

  def search(m, channel, string, max=4)
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
plugin.register("urls")
