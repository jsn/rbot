#-- vim:sw=2:et
#++
#
# :title: spotify library used at least in spotify and lastfm plugins
#
# Author:: Raine Virta <raine.virta@gmail.com>
#
# Copyright:: (C) 2009 Raine Virta
#
# License:: GPL v2

require 'rexml/document'
require 'cgi'

module ::Spotify
  class SpotifyObject
    def initialize(xml)
      @spotify_id = xml.attributes["href"]
    end

    def url
      id = @spotify_id[@spotify_id.rindex(':')+1..-1]
      method = self.class.to_s.split('::').last.downcase
      return "http://open.spotify.com/#{method}/#{id}"
    end
  end

  class Album < SpotifyObject
    attr_reader :name, :released, :artist

    def initialize(xml)
      super
      @name = xml.elements["name"].text
      if e = xml.elements["artist"]
        @artist = Artist.new(xml.elements["artist"])
      end
      if e = xml.elements["released"]
        @released = e.text.to_i
      end
    end
  end

  class Artist < SpotifyObject
    attr_reader :name

    def initialize(xml)
      super
      @name = xml.elements["name"].text
    end
  end

  class Track < SpotifyObject
    attr_reader :name, :artist, :album, :track_number

    def initialize(xml)
      super
      @name = xml.elements["name"].text
      @artist = Artist.new(xml.elements["artist"])
      @album = Album.new(xml.elements["album"])
      @track_number = xml.elements["track-number"].text.to_i
      @length = xml.elements["length"].text.to_f
    end

    def to_s
      str = "#{artist.name} – #{name} [#{album.name}"
      str << ", #{album.released}" if album.released
      str << "]"
    end
  end

  def self.get(service, method, query, page=1)
    query.tr!('-','')
    url = "http://ws.spotify.com/#{service}/1/#{method}?q=#{CGI.escape(query)}&page=#{page}"
    xml = Irc::Utils.bot.httputil.get(url)
    raise unless xml
    return REXML::Document.new(xml).root
  end

  def self.search(method, query, page=1)
    doc = get(:search, method, query, page)
    return nil if doc.elements["opensearch:totalResults"].text.to_i.zero?
    return Spotify.const_get(method.to_s.capitalize).new(doc.elements[method.to_s])
  end
end
