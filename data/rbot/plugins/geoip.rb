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

module ::GeoIP
  class InvalidHostError < RuntimeError; end
  class BadAPIError < RuntimeError; end

  HOST_NAME_REGEX  = /^[a-z0-9\-]+(?:\.[a-z0-9\-]+)*\.[a-z]{2,4}/i

  def self.valid_host?(hostname)
    hostname =~ HOST_NAME_REGEX ||
    hostname =~ Resolv::IPv4::Regex && (hostname.split(".").map { |e| e.to_i }.max <= 255)
  end

  def self.geoiptool(ip)
    url = "http://www.geoiptool.com/en/?IP="
    regexes  = {
      :country => %r{Country:.*?<a href=".*?" target="_blank"> (.*?)</a>}m,
      :region  => %r{Region:.*?<a href=".*?" target="_blank">(.*?)</a>}m,
      :city    => %r{City:.*?<td align="left" class="arial_bold">(.*?)</td>}m,
      :lat     => %r{Latitude:.*?<td align="left" class="arial_bold">(.*?)</td>}m,
      :lon     => %r{Longitude:.*?<td align="left" class="arial_bold">(.*?)</td>}m
    }
    res = {}
    raw = Irc::Utils.bot.httputil.get_response(url+ip)
    raw = raw.decompress_body(raw.raw_body)

    regexes.each { |key, regex| res[key] = Iconv.conv('utf-8', 'ISO-8859-1', raw.scan(regex).to_s) }

    return res
  end

  def self.kapsi(ip)
    url = "http://lakka.kapsi.fi:40086/lookup.yaml?host="
    yaml = Irc::Utils.bot.httputil.get(url+ip)
    return YAML::load(yaml)
  end

  def self.blogama(ip)
    url = "http://ipinfodb.com/ip_query.php?ip="
    debug "Requesting #{url+ip}"

    xml = Irc::Utils.bot.httputil.get(url+ip)

    if xml
      obj = REXML::Document.new(xml)
      debug "Found #{obj}"
      newobj = {
        :country => obj.elements["Response"].elements["CountryName"].text,
        :city => obj.elements["Response"].elements["City"].text,
        :region => obj.elements["Response"].elements["RegionName"].text,
      }
      debug "Returning #{newobj}"
      return newobj
    else
      raise InvalidHostError
    end
  end

  def self.resolve(hostname, api)
    raise InvalidHostError unless valid_host?(hostname)

    begin
      ip = Resolv.getaddress(hostname)
    rescue Resolv::ResolvError
      raise InvalidHostError
    end

    jump_table = {
        "blogama" => Proc.new { |ip| blogama(ip) },
        "kapsi" => Proc.new { |ip| kapsi(ip) },
        "geoiptool" => Proc.new { |ip| geoiptool(ip) },
    }

    raise BadAPIError unless jump_table.key?(api)

    return jump_table[api].call(ip)
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
  Config.register Config::ArrayValue.new('geoip.sources',
      :default => [ "blogama", "kapsi", "geoiptool" ],
      :desc => "Which API to use for lookups. Supported values: blogama, kapsi, geoiptool")

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

    geo = {:country => ""}
    begin
      apis = @bot.config['geoip.sources']
      apis.compact.each { |api|
        geo = GeoIP::resolve(host, api)
        if geo[:country] != ""
          break
        end
      }
    rescue GeoIP::InvalidHostError, RuntimeError
      if nick
        return _("#{nick}'s location could not be resolved")
      else
        return _("#{host} could not be resolved")
      end
    rescue GeoIP::BadAPIError
      return _("The owner configured me to use an API that doesn't exist, bug them!")
    end

    res = _("%{thing} is #{nick ? "from" : "located in"}") % {
      :thing   => (nick ? nick : Resolv::getaddress(host)),
      :country => geo[:country]
    }

    res << " %{city}" % {
      :city => geo[:city]
    } unless geo[:city].to_s.empty?

    res << " %{region}," % {
      :region  => geo[:region]
    } unless geo[:region].to_s.empty? || geo[:region] == geo[:city]

    res << " %{country}" % {
      :country => geo[:country]
    }

    return res
  end
end

plugin = GeoIpPlugin.new
plugin.map "geoip [:input]", :action => 'geoip', :thread => true
