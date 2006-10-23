require "shorturl"
require "uri"

class RubyURL < Plugin

  # return a help string when the bot is asked for help on this plugin
  def help(plugin, topic="")
    return "rubyurl <your long url>"
  end

  def shorten(m, params)
    if (params[:url] == "help")
      m.reply help(m.plugin)
      return
    end

    url = params[:url]
    begin
      to_uri = URI.parse(url)
      # We don't accept 'generic' URLs because almost everything gets in there
      raise URI::InvalidURIError if to_uri.class == URI::Generic
    rescue URI::InvalidURIError
      m.reply "#{url} doesn't look like an URL to me ..."
      return
    end

    short = WWW::ShortURL.shorten(url)

    m.reply "#{url} shortened to #{short} on RubyURL"
  end

end

# create an instance of the RubyURL class and register it as a plugin
rubyurl = RubyURL.new
rubyurl.map "rubyurl :url", :action => 'shorten'
