#-- vim:sw=2:et
#++
#
# :title: Geo IP Plugin
#
# Author:: Raine Virta <rane@kapsi.fi>
# Copyright:: (C) 2008 Raine Virta
# License:: GPL v2
#
# Resolves the geographic locations of users (network-wide) and IP addresses

module GeoIP
  GEO_IP = "http://www.geoiptool.com/en/?IP="
  REGEX  = {
    :country => %r{Country:.*?<a href=".*?" target="_blank"> (.*?)</a>}m,
    :region  => %r{Region:.*?<a href=".*?" target="_blank">(.*?)</a>}m,
    :city    => %r{City:.*?<td align="left" class="arial_bold">(.*?)</td>}m
  }


  def self.resolve(hostname)
    res = {}
    raw = Irc::Utils.bot.httputil.get_response(GEO_IP+hostname)
    raw = raw.decompress_body(raw.raw_body)

    REGEX.each { |key, regex| res[key] = Iconv.conv('utf-8', 'ISO-8859-1', raw.scan(regex).to_s) }

    return res
  end
end

class GeoIpPlugin < Plugin
  def help(plugin, topic="")
    "geoip [<user|hostname|ip>] => returns the geographic location of whichever has been given -- note: user can be anyone on the network"
  end

  def whois(m)
    # need to see if the whois reply was invoked by this plugin
    return unless m.whois[:nick] == @nick

    if m.target
      @bot.say @source, host2output(m.target.host, m.target.nick)
    else
      @bot.say @source, "no such user on "+@bot.server.hostname.split(".")[-2]
    end

    @nick, @source = nil
  end

  def geoip(m, params)
    if params.empty?
      m.reply host2output(m.source.host, m.source.nick)
    else
      if m.replyto.class == Channel

        # check if there is an user on the channel with nick same as input given
        user = m.replyto.users.find { |user| user.nick == params[:input] }

        if user
          m.reply host2output(user.host, user.nick)
          return
        end
      end

      # input is a host name or an IP
      if params[:input] =~ /[a-z0-9\-]+(?:\.[a-z0-9\-]+)*\.[a-z]{2,3}/i ||
         params[:input] =~ Resolv::IPv4::Regex
        m.reply host2output(params[:input])

      # assume input is a nick
      else
        @source = m.replyto
        @nick   = params[:input]

        @bot.whois(@nick)
      end
    end
  end

  def host2output(host, nick=nil)
    geo = GeoIP::resolve(host)

    if geo[:country].empty?
      return _("#{nick ? "#{nick}'s location" : host} could not be resolved")
    end

    res = _("%{thing} is #{nick ? "from" : "located in"}") % {
      :thing   => (nick ? nick : Resolv::getaddress(host)),
      :country => geo[:country]
    }

    res << " %{city}," % {
      :city => geo[:city]
    } unless geo[:city].empty?

    res << " %{country}" % {
      :country => geo[:country]
    }

    res << " (%{region})" % {
      :region  => geo[:region]
    } unless geo[:region].empty? || geo[:region] == geo[:city]

    return res
  end
end

plugin = GeoIpPlugin.new
plugin.map "geoip [:input]", :action => 'geoip'
