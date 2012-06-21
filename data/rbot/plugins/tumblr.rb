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
# TODO support other video providers (maybe detect embed codes?)
# TODO support image better (e.g. pages with a single big image)
# TODO customize caption/description format
# TODO do not reblog own posts (maybe?)

require 'rexml/document'
require 'cgi'

class TumblrPlugin < Plugin
  RBOT = CGI.escape("rbot #{$version.split.first}")
  WRITE_URL = "http://www.tumblr.com/api/write"
  REBLOG_URL = "http://www.tumblr.com/api/reblog"
  READ_URL = "http://%{user}.tumblr.com/api/read?id=%{id}"
  LOGIN = "email=%{email}&password=%{pwd}&group=%{group}&format=markdown&generator=" + RBOT
  PHOTO = "&type=photo&source=%{src}&click-through-url=%{src}"
  VIDEO = "&type=video&embed=%{src}"
  CAPTION = "&caption=%{desc}"
  LINK = "&type=link&url=%{src}"
  NAME = "&name=%{name}"
  DESC = "&description=%{desc}"
  REBLOG = "&post-id=%{id}&reblog-key=%{reblog}"
  COMMENT = "&comment=%{desc}"
  TAGS = "&tags=%{tags}"

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
    html_line = line ? CGI.escapeHTML(line) : line
    tags = line ? line.scan(/\[([^\]]+)\]/).flatten : []

    req = LOGIN % account
    ready = false
    api_url = WRITE_URL
    tumblr = options[:htmlinfo][:headers]['x-tumblr-user'].to_s rescue nil
    if tumblr
      id = url.match(/\/post\/(\d+)/)
      if id
        id = id[1]

        read_url = READ_URL % { :user => tumblr, :id => id}
        # TODO seems to return 503 a little too frequently
        xml = @bot.httputil.get(read_url)

        if xml
          reblog = REXML::Document.new(xml).elements["//post"].attributes["reblog-key"] rescue nil
          if reblog and not reblog.empty?
            api_url = REBLOG_URL
            data = REBLOG
            data << COMMENT
            html_line = CGI.escapeHTML("(via <a href=%{url}>%{tumblr}</a>" % {
              :url => url, :tumblr => tmblr
            }) unless html_line
            req << (data % {
              :id => id,
              :reblog => reblog,
              :desc => CGI.escape(html_line)
            })
            ready = true
          end
        end
      end
    end

    if not ready
      type = options[:htmlinfo][:headers]['content-type'].first rescue nil
      case type
      when /^image\/.*/
        data = PHOTO
        data << CAPTION if line
      else
        if url.match(%r{^http://(\w+\.)?(youtube\.com/watch.*|vimeo.com/\d+)})
          data = VIDEO
          data << CAPTION if line
        else
          data = LINK
          data << NAME if line
        end
      end
      data << TAGS unless tags.empty?
      req << (data % {
        :src => CGI.escape(url),
        :desc => CGI.escape(html_line),
        :tags => CGI.escape(tags.join(',')),
        :name => CGI.escape(line)
      })
    end

    debug "posting #{req.inspect}"
    resp  = @bot.httputil.post(api_url, req)
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
      group = params[:group] || Channel.npname(channel)
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
  :requirements => {:channel => Regexp::Irc::GEN_CHAN, :email => /\S+@\S+/, :group => /[A-Za-z\-.]+/}

