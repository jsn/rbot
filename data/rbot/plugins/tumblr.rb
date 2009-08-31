#-- vim:sw=2:et
#++
#
# :title: tumblr interface
#
# Author:: Giuseppe Bilotta <giuseppe.bilotta@gmail.com>
# Copyright:: (C) 2009 Giuseppe Bilotta
# License:: GPLv2
#
# Submit URLs to channel-specific tumblr accounts
#
# TODO reblog tumblr URLs
# TODO support video better (e.g. Vimeo or anything else with embed)
# TODO support image better (e.g. pages with a single big image)
# TODO customize caption/description format

require 'rexml/document'
require 'cgi'

class TumblrPlugin < Plugin
  RBOT = CGI.escape("rbot #{$version.split.first}")
  WRITE_URL = "http://www.tumblr.com/api/write"
  LOGIN = "email=%{email}&password=%{pwd}&group=%{group}&format=markdown&generator=" + RBOT
  PHOTO = "&type=photo&source=%{src}&click-through-url=%{src}"
  VIDEO = "&type=video&embed=%{src}"
  CAPTION = "&caption=%{desc}"
  LINK = "&type=link&url=%{src}"
  DESC = "&name=%{desc}"

  def help(plugin, topic="")
    case topic
    when "configure"
      "tumblr configure [<channel>]: show credentials used for channel <channel> (default: current).    tumblr configure [<channel>] <email> <password> [<group>] => post links from channel <channel> (default: current) to group <group> (default: name of channel) using the given tumblr credentials"
    when "deconfigure"
      "tumblr deconfigure [<channel>]: forget credentials for channel <channel> (default: current)."
    else
      "post links, photos and videos to a channel-specific tumblr. topics: configure, deconfigure"
    end
  end

  def event_url_added(url, options={})
    return unless options.key? :channel
    chan = options[:channel]
    return unless @registry.key? chan

    account = @registry[chan]

    line = options[:ircline]
    line = nil if line and line.empty?
    if line and nick = options[:nick]
      line = "<#{nick}> #{line}"
    end

    req = LOGIN % account
    type = options[:htmlinfo][:headers]['content-type'].first rescue nil
    case type
    when /^image\/.*/
      data = PHOTO
      data << CAPTION if line
    else
      if url.match(%r{^http://(\w+\.)?youtube\.com/watch.*})
        data = VIDEO
        data << CAPTION if line
      else
        data = LINK
        data << DESC if line
      end
    end
    req << (data % { :src => CGI.escape(url), :desc => CGI.escape(line) })
    debug "posting #{req.inspect}"
    resp  = @bot.httputil.post(WRITE_URL, req)
    debug "tumblr response: #{resp.inspect}"
  end

  def configuration(m, params={})
    channel = params[:channel] || m.channel
    if not channel
      m.reply _("Please specify a channel")
      return
    end
    if not @registry.key? channel
      m.reply _("No tumblr credentials set for %{chan}" % { :chan => channel })
      return false
    end

    account = @registry[channel]

    account[:pwd] = _("<hidden>") if m.public?
    account[:chan] = channel

    m.reply _("Links on %{chan} will go to %{group} using account %{email} and password %{pwd}" % account)
  end

  def deconfigure(m, params={})
    channel = params[:channel] || m.channel
    if not channel
      m.reply _("Please specify a channel")
      return
    end
    if not @registry.key? channel
      m.reply _("No tumblr credentials set for %{chan}" % { :chan => channel })
      return false
    end

    @registry.delete channel

    m.reply _("Links on %{chan} will not be posted to tumblr anymore" % {:chan => channel})
  end

  def configure(m, params={})
    channel = params[:channel] || m.channel
    if not channel
      m.reply _("Please specify a channel")
      return
    end
    if @registry.key? channel
      m.reply _("%{chan} already has credentials configured" % { :chan => channel })
    else
      group = params[:group] || channel[1..-1]
      group << ".tumblr.com" unless group.match(/\.tumblr\.com/)
      @registry[channel] = {
        :email => CGI.escape(params[:email]),
        :pwd => CGI.escape(params[:pwd]),
        :group => CGI.escape(group)
      }

    end

    return configuration(m, params)
  end

end

plugin = TumblrPlugin.new

plugin.default_auth('*', false)

plugin.map 'tumblr configure [:channel]', :action => :configuration
plugin.map 'tumblr deconfigure [:channel]', :action => :deconfigure
plugin.map 'tumblr configure [:channel] :email :pwd [:group]',
  :action => :configure,
  :requirements => {:channel => Regexp::Irc::GEN_CHAN, :email => /.+@.+/, :group => /[A-Za-z-]+/}

