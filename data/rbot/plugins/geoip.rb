#-- vim:sw=2:et
#++
#
# :title: Geo IP Plugin
#
# Author:: Raine Virta <rane@kapsi.fi>
# Copyright:: (C) 2008 Raine Virta
# License:: GPL v2
#
# Resolves the geographic locations of users and IP addresses

module GeoIP
  GEO_IP = "http://www.geoiptool.com/en/?IP="

  def self.resolve(hostname)
    raw = Irc::Utils.bot.httputil.get(GEO_IP+hostname, :cache => true)

    {
      :country => raw.scan(%r{Country:.*?<a href=".*?" target="_blank"> (.*?)</a>}m).to_s,
      :region  => raw.scan(%r{Region:.*?<a href=".*?" target="_blank">(.*?)</a>}m).to_s,
      :city    => raw.scan(%r{City:.*?<td align="left" class="arial_bold">(.*?)</td>}m).to_s
    }
  end
end

class GeoIpPlugin < Plugin
  def help(plugin, topic="")
    "geoip [<user|hostname|ip>] => returns the geographic location of whichever has been given"
  end

  def geoip(m, params)
    if params.empty?
      m.reply host2output(m.source.host, m.source.nick)
    else
      if m.replyto.class == Channel
        # check if there is an user with nick same as input given
        user = m.replyto.users.find { |user| user.nick == params[:input] }

        if user
          m.reply host2output(user.host, user.nick)
          return
        end
      end

      if params[:input] =~ /[a-z0-9\-]+(?:\.[a-z0-9\-]+)*\.[a-z]{2,3}/i ||
         params[:input] =~ Resolv::IPv4::Regex
        m.reply host2output(params[:input])
      else
        m.reply "invalid input"
      end
    end
  end

  def host2output(host, nick=nil)
    geo = GeoIP::resolve(host)

    if geo[:country].empty?
      return _("#{host} could not be resolved")
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
