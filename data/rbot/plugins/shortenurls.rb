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
  # starting from about shorturl 0.8.4, the WWW module is not defined
  include WWW rescue nil

  Config.register Config::ArrayValue.new('shortenurls.services_blacklist',
    :default => ['rubyurl', 'shorterlink'],
    :requires_rescan => true,
    :desc => "List of nonfunctioning shorturl services")
  Config.register Config::StringValue.new('shortenurls.favorite_service',
    :default => 'tinyurl',
    :desc => "Default shortening service. Probably only applies when other plugins " +
             "use this one for shortening")

  attr_accessor :services
  def initialize
    super
    @blacklist = @bot.config['shortenurls.services_blacklist'].map { |s| s.intern }
    # Instead of catering for all the services, we only pick the ones with 'link' or 'url' in the name
    @services = ShortURL.valid_services.select { |service| service.to_s =~ /(?:link|url)/ } - @blacklist
    if @services.include?(:rubyurl)
      @services << :shorturl
    end
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
      return nil
    end
    begin
      to_uri = URI.parse(url)
      # We don't accept 'generic' URLs because almost everything gets in there
      raise URI::InvalidURIError if to_uri.class == URI::Generic
    rescue URI::InvalidURIError
      m.reply "#{url} doesn't look like an URL to me ..." unless params[:called]
      return nil
    end

    if params.has_key? :service
      service = params[:service]
    elsif m != nil and m.plugin != nil
      service = m.plugin
    else
      service = @bot.config['shortenurls.favorite_service']
    end
    service = service.to_sym
    service = :rubyurl if service == :shorturl

    tried = []
    short = nil

    begin
      tried << service
      raise InvalidService, "#{service} blacklisted" if @blacklist.include?(service)
      short = ShortURL.shorten(url, service)
      raise InvalidService, "#{service} returned an empty string for #{url}" unless short and not short.empty?
    rescue InvalidService
      pool = services - tried
      if pool.empty?
        m.reply "#{service} failed, and I don't know what else to try next" unless params[:called]
        return nil
      else
        service = pool.pick_one
        m.reply "#{tried.last} failed, I'll try #{service} instead" unless params[:called]
        retry
      end
    end

    m.reply "#{url} shortened to #{short}" unless params[:called]
    return short
  end

end

# create an instance of the RubyURL class and register it as a plugin
plugin = ShortenURLs.new

plugin.services.each { |service|
  plugin.map "#{service} :url", :action => 'shorten'
}
