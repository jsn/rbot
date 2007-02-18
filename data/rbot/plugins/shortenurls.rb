#-- vim:sw=2:et
#++
#
# :title: ShortURL plugin for rbot
#
# Author:: Giuseppe Bilotta <giuseppe.bilotta@gmail.com>
# Copyright:: (C) 2007 Giuseppe Bilotta
# License:: GPL v2
#
# Plugin to handle ShortURL, merges the funcionality of the old rubyurl and tinyurl plugins
# Note that it's called ShortenURLs and not ShortURL, to prevent conflicts with
# the actual ruby package used

require "shorturl"
require "uri"

class ShortenURLs < Plugin
  include WWW

  attr_accessor :services
  def initialize
    super
    # Instead of catering for all the services, we only pick the ones with 'link' or 'url' in the name
    @services = ShortURL.valid_services.select { |service| service.to_s =~ /(?:link|url)/ } << :shorturl
  end

  # return a help string when the bot is asked for help on this plugin
  def help(plugin, topic="")
    return "shorten urls. syntax: <service> <your long url> => creates a shortened url using the required service (choose between #{@services.join(', ')}). Example: #{@bot.nick}, tinyurl http://some.long.url/wow-this-is/really-long.html"
  end

  # do the dirty job. This method can be called by other plugins, in which case you
  # should set the :called param to true
  def shorten(m, params)
    url = params[:url]
    if url == "help"
      m.reply help(m.plugin) unless params[:called]
      return
    end
    begin
      to_uri = URI.parse(url)
      # We don't accept 'generic' URLs because almost everything gets in there
      raise URI::InvalidURIError if to_uri.class == URI::Generic
    rescue URI::InvalidURIError
      m.reply "#{url} doesn't look like an URL to me ..." unless params[:called]
      return
    end

    service = params[:service] || m.plugin.to_sym
    service = :rubyurl if service == :shorturl

    short = WWW::ShortURL.shorten(url, service)

    if params[:called]
      return short
    else
      m.reply "#{url} shortened to #{short}"
    end
  end

end

# create an instance of the RubyURL class and register it as a plugin
plugin = ShortenURLs.new

plugin.services.each { |service|
  plugin.map "#{service} :url", :action => 'shorten'
}
