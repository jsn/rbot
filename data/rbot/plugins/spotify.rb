#-- vim:sw=2:et
#++
#
# :title: spotify plugin for rbot
#
# Author:: Raine Virta <raine.virta@gmail.com>
#
# Copyright:: (C) 2009 Raine Virta
#
# License:: GPL v2

class SpotifyPlugin < Plugin
  def initialize
    super

    unless Object.const_defined?('Spotify')
      raise 'Spotify module not found (lib_spotify plugin probably not enabled)'
    end
  end

  def help(plugin, topic)
    _("spotify plugin - usage: spotify <spotify>, spotify artist <artist>, spotify album <album>")
  end

  def search(m, params)
    method = params[:method] || 'track'
    begin
      result = Spotify.search(method, params[:query].to_s)
    rescue
      m.reply "problems connecting to Spotify"
    end

    if result.nil?
      m.reply "no results"
      return
    end

    case method
    when 'track'
      reply = _("%{b}%{artist}%{b} – %{track}") % {
        :artist => result.artist.name,
        :track => result.name,
        :b => Bold
      }

      if result.album.released
        reply << _(" [%{u}%{album}%{u}, %{released}]") % {
          :released => result.album.released,
          :album => result.album.name,
          :u => Underline
        }
      else
        reply << _(" [%{u}%{album}%{u}]") % { :album => result.album.name, :u => Underline }
      end

      reply << _(" — %{url}") % { :url => result.url }
    when 'artist'
      reply = _("%{b}%{artist}%{b} — %{url}") % {
        :b => Bold,
        :artist => result.name,
        :url => result.url
      }
    when 'album'
      reply = _("%{b}%{artist}%{b} – %{u}%{album}%{u} — %{url}") % {
        :b => Bold,
        :u => Underline,
        :artist => result.artist.name,
        :album => result.name,
        :url => result.url
      }
    end

    m.reply reply
  end
end

plugin = SpotifyPlugin.new
plugin.map 'spotify [:method] *query', :action => :search, :requirements => { :method => /track|artist|album/ }
