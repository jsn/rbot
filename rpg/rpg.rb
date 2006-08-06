# Plugin for the Ruby IRC bot (http://linuxbrit.co.uk/rbot/)
#
# Little IRC game
#
# (c) 2006 Mark Kretschmann <markey@web.de>
# Licensed under GPL V2.


load '/home/eean/.rbot/plugins/rpg_creatures.rb'

class Map

  attr_accessor :map

  def initialize
    # Maps are 16x16 
    # X = player spawn, O = Orc, S = Slime 
    str = <<-END
----------------
| S |          |
|   |  |-----  |
|      |       |
|---|  |       |
|   |O |       |
|   |  --------|
|   |          |
|   | ----  |O |
|   |S|  |  |--|
|   | |  |     |
|---| |  |     |
|X    |  |     |
|------  |     |
|        |     |
----------------
    END

    @map = str.split( "\n")
  end


  def at( x, y )
    @map[y][x].chr
  end  


  def wall?( x, y )
    s = at( x, y)
    s == '|' or s == '-'
  end

end


class Game

  attr_accessor :channel, :players, :map, :party_pos
  Party_Pos = Struct.new( :x, :y )

  def initialize( channel, bot )
    @channel = channel
    @bot = bot
    @players = Hash.new

    @map = Map.new
    x, y = 0, 0
    m = @map.map
    m.length.times { |y| x = m[y].index( 'X' ); break if x != nil } 
    @party_pos = Party_Pos.new( x, y )

  end


  def say( text )
    @bot.say( @channel, text )
  end  

end


class RpgPlugin < Plugin

  def initialize
    super

    @games = Hash.new
  end


  def help( plugin, topic="" )
    "IRC RPG. Commands: 'spawn player', 'spawn monster', 'attack <target>', 'look [object]', 'stats'."
  end

#####################################################################
# Core Methods
#####################################################################

  # Returns new Game instance for channel, or existing one
  #
  def get_game( m )
      channel = (m.target == @bot.nick) ? m.sourcenick : m.target 

      unless @games.has_key?( channel )
          @games[channel] = Game.new( channel, @bot )
      end

      return @games[channel]
  end


  def schedule( g )
    # Check for death:
    g.players.each_value do |p|
      if p.hp < 0
        g.say( "#{p.name} dies from his injuries." )
        g.players.delete( p.name )        
      end  
    end

    # Let monsters act:
    g.players.each_value do |p|
      if p.is_a?( Monster )
        p.act( g )
      end
    end
  end


  def spawned?( g, nick )
    if g.players.has_key?( nick )
      return true
    else
      g.say( "You have not joined the game. Use 'spawn player' to join." )
      return false  
    end
  end


  def target_spawned?( g, target )
    if g.players.has_key?( target )
      return true
    else  
      g.say( "There is noone named #{target} near.." )
      return false
    end
  end

#####################################################################
# Command Handlers
#####################################################################

  def handle_spawn_player( m, params )
    g = get_game( m )

    p = Player.new  
    p.name = m.sourcenick
    g.players[p.name] = p
    m.reply "Player #{p.name} enters the game."
  end


  def handle_spawn_monster( m, params )
    g = get_game( m )
    p = Monster.monsters[rand( Monster.monsters.length )].new  

    # Make sure we don't have multiple monsters with same name (FIXME)
    a = [0]
    g.players.each_value { |x| a << x.name[-1,1].to_i if x.name.include? p.name }
    p.name += ( a.sort.last + 1).to_s

    g.players[p.name] = p
    m.reply "A #{p.player_type} enters the game. ('#{p.name}')"
  end


  def handle_attack( m, params )
    g = get_game( m )
    return unless spawned?( g, m.sourcenick )
    return unless target_spawned?( g, params[:target] )
 
    g.players[m.sourcenick].attack( g, g.players[params[:target]] )
    schedule( g )
  end


  def handle_look( m, params )
    g = get_game( m )
    return unless spawned?( g, m.sourcenick )

    if params[:object] == nil
      if g.players.length == 1
        m.reply( "#{m.sourcenick}: You are alone." )
      else
        objects = []
        g.players.each_value { |x| objects << x.name unless x.name == m.sourcenick }
        m.reply( "#{m.sourcenick}: You see the following objects: #{objects.join( ', ' )}." )
      end

      debug "MAP_LENGTH:  #{g.map.map.length}"
      debug "PARTY_POS:   x:#{g.party_pos.x}  y:#{g.party_pos.y}"

      x = g.party_pos.x  
      y = g.party_pos.y


      debug "MAP NORTH: #{g.map.at( x, y-1 )}"

      north = g.map.wall?( x, y-1 ) ? "a wall" : "open space"
      east  = g.map.wall?( x+1, y ) ? "a wall" : "open space"
      south = g.map.wall?( x, y+1 ) ? "a wall" : "open space"
      west  = g.map.wall?( x-1, y ) ? "a wall" : "open space"

      m.reply( "In the north is #{north}, east is #{east}, south is #{south}, and in the west you see #{west}." )
    else
      p = nil
      g.players.each_value { |x| p = x if x.name == params[:object] }
      if p == nil
        m.reply( "#{m.sourcenick}: There is no #{params[:object]} here." )
      else
        m.reply( "#{m.sourcenick}: #{p.description}" )   
      end
    end  
  end


  def handle_go( m, params )
  end


  def handle_stats( m, params )
    begin

    g = get_game( m )
    return unless spawned?( g, m.sourcenick )

    p = g.players[m.sourcenick]
    m.reply( "Stats for #{m.sourcenick}: HP:#{p.hp}  XP:#{p.xp}  THAC0:#{p.thac0}  AC:#{p.ac}  HD:#{p.hd}" )
   
    rescue => e
    m.reply e.inspect
    end
  end

end
  

plugin = RpgPlugin.new
plugin.register( "rpg" )

plugin.map 'spawn player',   :action => 'handle_spawn_player'
plugin.map 'spawn monster',  :action => 'handle_spawn_monster' 
plugin.map 'attack :target', :action => 'handle_attack' 
plugin.map 'look :object',   :action => 'handle_look',         :defaults => { :object => nil }
plugin.map 'go :direction',  :action => 'handle_go' 
plugin.map 'stats',          :action => 'handle_stats'


