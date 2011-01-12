#################################################################
# IP Lookup Plugin
# ----------------------------
# by Chris Gahan (chris@ill-logic.com)
#
# Purpose:
# ------------------
# Lets you lookup the owner and their address for any IP address
# or IRC user.
#
#################################################################

require 'socket'
require 'resolv'

#################################################################
## ARIN Whois module...
##

module ArinWhois

  class Chunk < Hash
    def customer?
      keys.grep(/^(City|Address|StateProv|(Org|Cust)Name)$/).any?
    end

    def network?
      keys.grep(/^(CIDR|NetHandle|Parent)$/).any?
    end

    def contact?
      keys.grep(/^(R|Org)(Tech|Abuse)(Handle|Name|Phone|Email)$/).any?
    end

    def valid?
      customer? or network? or contact?
    end

    def owner
      self[keys.grep(/^(Org|Cust)Name$/).first]
    end

    def location
      [ self['City'], self['StateProv'], self['Country'] ].compact.join(', ')
    end

    def address
      [ self['Address'], location, self['PostalCode'] ].compact.join(', ')
    end

  end

  class ArinWhoisParser

    def initialize(data)
      @data = data
    end

    def split_array_at(a, &block)
      return a unless a.any?
      a = a.to_a

      results = []
      last_cutpoint = 0

      a.each_with_index do |el,i|
        if block.call(el)
          unless i == 0
            results << a[last_cutpoint...i]
            last_cutpoint = i
          end
        end
      end

      if last_cutpoint < a.size or last_cutpoint == 0
        results << a[last_cutpoint..-1]
      end

      results
    end

    # Whois output format
    # ------------------------
    # Owner info block:
    #   {Org,Cust}Name
    #   Address
    #   City
    #   StateProv
    #   PostalCode
    #   Country (2-digit)
    #
    # Network Information:
    #   CIDR (69.195.25.0/25)
    #   NetHandle (NET-72-14-192-0-1)
    #   Parent (NET-72-0-0-0-0)
    #
    # Contacts:
    #   ({R,Org}{Tech,Abuse}{Handle,Name,Phone,Email})*

    def parse_chunks
      return if @data =~ /^No match found /
      chunks = @data.gsub(/^# ARIN WHOIS database, last updated.+/m, '').scan(/(([^\n]+\n)+\n)/m)
      chunks.map do |chunk|
        result = Chunk.new

        chunk[0].scan(/([A-Za-z]+?):(.*)/).each do |tuple|
          tuple[1].strip!
          result[tuple[0]] = tuple[1].empty? ? nil : tuple[1]
        end

        result
      end
    end


    def get_parsed_data
      return unless chunks = parse_chunks

      results = split_array_at(chunks) {|chunk|chunk.customer?}
      results.map do |data|
        {
          :customer => data.select{|x|x.customer?}[0],
          :net      => data.select{|x|x.network?}[0],
          :contacts => data.select{|x|x.contact?}
        }
      end
    end

    # Return a hash with :customer, :net, and :contacts info filled in.
    def get_most_specific_owner
      return unless datas = get_parsed_data

      datas_with_bitmasks = datas.map do |data|
        bitmask = data[:net]['CIDR'].split('/')[1].to_i
        [bitmask, data]
      end
      #datas_with_bitmasks.sort.each{|x|puts x[0]}
      winner = datas_with_bitmasks.sort[-1][1]
    end

  end # of class ArinWhoisParser

module_function

  def raw_whois(query_string, host)
    s = TCPsocket.open(host, 43)
    s.write(query_string+"\n")
    ret = s.read
    s.close
    return ret
  end

  def lookup(ip)
    data = raw_whois("+#{ip}", 'whois.arin.net')
    arin = ArinWhoisParser.new data
    arin.get_most_specific_owner
  end

  def lookup_location(ip)
    result = lookup(ip)
    result[:customer].location
  end

  def lookup_address(ip)
    result = lookup(ip)
    result[:customer].address
  end

  def lookup_info(ip)
    if result = lookup(ip)
      "#{result[:net]['CIDR']} => #{result[:customer].owner} (#{result[:customer].address})"
    else
      "Address not found."
    end
  end

end



#################################################################
## The Plugin
##

class IPLookupPlugin < Plugin
  def help(plugin, topic="")
    "iplookup [ip address / domain name] => lookup info about the owner of the IP address from the ARIN whois database"
  end

  def iplookup(m, params)
    reply = ""
    if params[:domain].match(/^#{Regexp::Irc::HOSTADDR}$/)
      ip = params[:domain]
    else
      begin
        ip = Resolv.getaddress(params[:domain])
        reply << "#{params[:domain]} | "
      rescue => e
        m.reply "#{e.message}"
        return
      end
    end

    reply << ArinWhois.lookup_info(ip)

    m.reply reply
  end

  def userip(m, params)
    m.reply "not implemented yet"
    #users = @channels[m.channel].users
    #m.reply "users = #{users.inspect}"
    #m.reply @bot.sendq("WHO #{params[:user]}")
  end

end

plugin = IPLookupPlugin.new
plugin.map 'iplookup :domain', :action => 'iplookup', :thread => true
plugin.map 'userip :user', :action => 'userip', :requirements => {:user => /\w+/}, :thread => true


if __FILE__ == $0
  include ArinWhois
  data = open('whoistest.txt').read
  c = ArinWhoisParser.new data
  puts c.get_parsed_data.inspect
end
