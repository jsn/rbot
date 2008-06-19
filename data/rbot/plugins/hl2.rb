#-- vim:sw=2:et
#++
#
# :title: Half-Life 2 plugin for rbot
#
# Author:: Ole Christian Rynning <oc@rynning.no>
# Author:: Andrew Northall <cubehat@gmail.com>
# Copyright:: (C) 2006 Ole Christian Rynning & Andrew Northall
# License:: GPL v2
#
# Simple Half-Life 2 (Source Engine) plugin to query online
# servers to see if its online and kicking and how many users.
#
# Added 2 seconds timeout to the response. And sockets are now
# closing properly.
#
# Server presets can be added by using 'hl2 add name addr:port'
# and 'hl2 del name'. Once presets are added they are accessed
# as 'hl2 name'.

require 'socket'
require 'timeout'

class HL2Plugin < Plugin

  A2S_INFO = "\xFF\xFF\xFF\xFF\x54\x53\x6F\x75\x72\x63\x65\x20\x45\x6E\x67\x69\x6E\x65\x20\x51\x75\x65\x72\x79\x00"

  TIMEOUT = 2

  def a2s_info(addr, port)
    socket = UDPSocket.new()
    begin
      socket.send(A2S_INFO, 0, addr, port.to_i)
      response = nil

      timeout(TIMEOUT) do
        response = socket.recvfrom(1400,0)
      end
    rescue Exception => e
      error e
    end

    socket.close()
    response ? response.first.unpack("iACZ*Z*Z*Z*sCCCaaCCZ*") : nil
  end

  def help(plugin, topic="")
    case topic
    when ""
      return "hl2 'server:port'/'preset name' => show basic information about the given server."
    when "add"
      return "hl2 add 'name' 'server:port' => add a preset."
    when "del"
      return "hl2 del 'name' => remove a present."
    end
  end

  def hl2(m, params)
    addr, port = params[:conn_str].split(':')
    if port == nil
      @registry.each_key do
        |key|
        if addr.downcase == key.downcase
          addr, port = @registry[key]
        end
      end
    end
    m.reply "invalid server" if port == nil
    return if port == nil
    info = a2s_info(addr, port)
    if info
      m.reply "#{info[3]} (#{info[6]}): #{info[8]}/#{info[9]} - #{info[4]}"
    else
      m.reply "Couldn't connect to #{params[:conn_str]}"
    end
  end

  def add_server(m, params)
    @registry[params[:name]] = params[:conn_str].split(':')
    m.okay
  end

  def rem_server(m, params)
    if @registry.has_key?(params[:name]) == false
      m.reply "but i don't know it!"
      return
    end
    @registry.delete params[:name]
    m.okay
  end
end

plugin = HL2Plugin.new
plugin.default_auth('edit', false)
plugin.map 'hl2 :conn_str', :thread => true
plugin.map 'hl2 add :name :conn_str', :thread => true, :action => :add_server, :auth_path => 'edit'
plugin.map 'hl2 del :name', :thread => true, :action => :rem_server, :auth_path => 'edit'
