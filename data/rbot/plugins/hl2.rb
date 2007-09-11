#-- vim:sw=2:et
#++
#
# :title: Half-Life 2 plugin for rbot
#
# Author:: Ole Christian Rynning <oc@rynning.no>
# Copyright:: (C) 2006 Ole Christian Rynning
# License:: GPL v2
#
# Simple Half-Life 2 (Source Engine) plugin to query online
# servers to see if its online and kicking and how many users.
#
# Added 2 seconds timeout to the response. And sockets are now
# closing properly.

require 'socket'
require 'timeout'

class HL2Plugin < Plugin

  A2S_INFO = "\xFF\xFF\xFF\xFF\x54\x53\x6F\x75\x72\x63\x65\x20\x45\x6E\x67\x69\x6E\x65\x20\x51\x75\x65\x72\x79\x00"

  TIMEOUT = 2

  def a2s_info(addr, port)
    socket = UDPSocket.new()
    socket.send(A2S_INFO, 0, addr, port.to_i)
    response = nil

    begin
      timeout(TIMEOUT) do
        response = socket.recvfrom(1400,0)
      end
    rescue Exception
    end

    socket.close()
    response ? response.first.unpack("iACZ*Z*Z*Z*sCCCaaCCZ*") : nil
  end

  def help(plugin, topic="")
    "hl2 'server:port' => show basic information about the given server"
  end

  def hl2(m, params)
    addr, port = params[:conn_str].split(':')
    info = a2s_info(addr, port)
    if info != nil
      m.reply "#{info[3]} is online with #{info[8]}/#{info[9]} players."
    else
      m.reply "Couldn't connect to #{params[:conn_str]}"
    end
  end

end

plugin = HL2Plugin.new
plugin.map 'hl2 :conn_str', :thread => true

