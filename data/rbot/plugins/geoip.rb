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
  class InvalidHostError < RuntimeError; end

  GEO_IP_PRIMARY   = "http://lakka.kapsi.fi:40086/lookup.yaml?host="
  GEO_IP_SECONDARY = "http://www.geoiptool.com/en/?IP="
  HOST_NAME_REGEX  = /^[a-z0-9\-]+(?:\.[a-z0-9\-]+)*\.[a-z]{2,4}/i

  REGEX  = {
    :country => %r{Country:.*?<a href=".*?" target="_blank"> (.*?)</a>}m,
    :region  => %r{Region:.*?<a href=".*?" target="_blank">(.*?)</a>}m,
    :city    => %r{City:.*?<td align="left" class="arial_bold">(.*?)</td>}m,
    :lat     => %r{Latitude:.*?<td align="left" class="arial_bold">(.*?)</td>}m,
    :lon     => %r{Longitude:.*?<td align="left" class="arial_bold">(.*?)</td>}m
  }

  def self.valid_host?(hostname)
    hostname =~ HOST_NAME_REGEX ||
    hostname =~ Resolv::IPv4::Regex && (hostname.split(".").map { |e| e.to_i }.max <= 255)
  end

  def self.resolve(hostname)
    raise InvalidHostError unless valid_host?(hostname)

    yaml = Irc::Utils.bot.httputil.get(GEO_IP_PRIMARY+hostname)

    if yaml
      return YAML::load(yaml)
    else
      res = {}
      raw = Irc::Utils.bot.httputil.get_response(GEO_IP_SECONDARY+hostname)
      raw = raw.decompress_body(raw.raw_body)

      REGEX.each { |key, regex| res[key] = Iconv.conv('utf-8', 'ISO-8859-1', raw.scan(regex).to_s) }

      return res
    end
  end
end

class Stack
  def initialize
    @hash = {}
  end

  def [](nick)
    @hash[nick] = [] unless @hash[nick]
    @hash[nick]
  end

  def has_nick?(nick)
    @hash.has_key?(nick)
  end

  def clear(nick)
    @hash.delete(nick)
  end
end

class GeoIpPlugin < Plugin
  def help(plugin, topic="")
    "geoip [<user|hostname|ip>] => returns the geographic location of whichever has been given -- note: user can be anyone on the network"
  end

  def initialize
    super

    @stack = Stack.new
  end

  def whois(m)
    nick = m.whois[:nick].downcase

    # need to see if the whois reply was invoked by this plugin
    return unless @stack.has_nick?(nick)

    if m.target
      msg = host2output(m.target.host, m.target.nick)
    else
      msg = "no such user on "+@bot.server.hostname.split(".")[-2]
    end
    @stack[nick].each do |source|
      @bot.say source, msg
    end

    @stack.clear(nick)
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
      if GeoIP::valid_host?(params[:input])
         m.reply host2output(params[:input])

      # assume input is a nick
      elsif params[:input] !~ /\./
        nick = params[:input].downcase

        @stack[nick] << m.replyto
        @bot.whois(nick)
      else
        m.reply "invalid input"
      end
    end
  end

  def host2output(host, nick=nil)
    return "127.0.0.1 could not be res.. wait, what?" if host == "127.0.0.1"

    begin
      geo = GeoIP::resolve(host)

      raise if geo[:country].empty?
    rescue GeoIP::InvalidHostError, RuntimeError
      return _("#{nick ? "#{nick}'s location" : host} could not be resolved")
    end

    res = _("%{thing} is #{nick ? "from" : "located in"}") % {
      :thing   => (nick ? nick : Resolv::getaddress(host)),
      :country => geo[:country]
    }

    res << " %{city}," % {
      :city => geo[:city]
    } unless geo[:city].to_s.empty?

    res << " %{country}" % {
      :country => geo[:country]
    }

    res << " (%{region})" % {
      :region  => geo[:region]
    } unless geo[:region].to_s.empty? || geo[:region] == geo[:city]

    return res
  end
end

plugin = GeoIpPlugin.new
plugin.map "geoip [:input]", :action => 'geoip', :thread => true
