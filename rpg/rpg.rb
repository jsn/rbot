# Plugin for the Ruby IRC bot (http://linuxbrit.co.uk/rbot/)
#
# Little IRC game
#
# (c) 2006 Mark Kretschmann <markey@web.de>
# Licensed under GPL V2.


load '/home/eean/.rbot/plugins/rpg_creatures.rb'

class Map

  attr_accessor :map, :legend

  def initialize
    @legend = { 'O' => Orc, 'S' => Slime }

    # Maps are 16x16 
    # X = player spawn 
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
|X   O|  |     |
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

  attr_accessor :channel, :objects, :map, :party_pos

  def initialize( channel, bot )
    @channel = channel
    @bot = bot
    @objects = Hash.new
    @party_pos = Position.new

    @map = Map.new
    x, y = 0, 0
    m = @map.map

    # Read the map and spawn objects
    m.length.times { |y|
      m[y].length.times { |x| 
        c = @map.at( x, y )
        case c
        when ' ', '-', '|'
          next
        when 'X'
          @party_pos.x, @party_pos.y = x, y
          next
        else
          o = spawn( @map.legend[c] )
          o.pos.x, o.pos.y = x, y
        end  
      }
    }

  end


  def set_players_pos( x, y )
    @objects.each { |c| c.pos.x, c.pos.y = x, y if c.instance_of?( Player ) }
  end
     

  def spawn( klass, name = nil )
    o = klass.new
    if name
      o.name = name
    else
      # Make sure we have unique names for all objects: orc1, orc2.. 
      a = [0]
      objects.each_value { |x| a << x.name[-1,1].to_i if x.name.include? o.name }
      o.name += ( a.sort.last + 1).to_s
    end

    objects[o.name] = o
    o
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
    "IRC RPG. Commands: 'spawn player', 'spawn monster', 'attack <target>', 'look [object]', 'stats', 'go <north|n|east|e|south|s|west|w>'."
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
    g.objects.each_value do |p|
      if p.hp < 0
        g.say( "#{p.name} dies from his injuries." )
        g.objects.delete( p.name )        
      end  
    end

    # Let monsters act:
    g.objects.each_value do |p|
      if p.is_a?( Monster )
        p.act( g )
      end
    end
  end


  def spawned?( g, nick )
    if g.objects.has_key?( nick )
      return true
    else
      g.say( "You have not joined the game. Use 'spawn player' to join." )
      return false  
    end
  end


  def target_spawned?( g, target )
    if g.objects.has_key?( target )
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

    o = g.spawn( Player, m.sourcenick )
    o.pos = g.party_pos.dup
    m.reply "Player #{o.name} enters the game."
  end


  def handle_spawn_monster( m, params )
    g = get_game( m )

    o = g.spawn( Monster.monsters[rand( Monster.monsters.length )] ) 
    o.pos = g.party_pos.dup
    m.reply "A #{o.object_type} enters the game. ('#{o.name}')"
  end


  def handle_attack( m, params )
    g = get_game( m )
    return unless spawned?( g, m.sourcenick )
    return unless target_spawned?( g, params[:target] )
 
    g.objects[m.sourcenick].attack( g, g.objects[params[:target]] )
    schedule( g )
  end


  def handle_look( m, params )
    g = get_game( m )
    return unless spawned?( g, m.sourcenick )

    p = g.objects[m.sourcenick]
    x, y = p.pos.x, p.pos.y
    objects_near = []
    g.objects.each_value { |o| debug( o.pos ); objects_near << o if o.pos == p.pos and o != p }

    if params[:object] == nil
      if objects_near.empty?
        m.reply( "#{m.sourcenick}: You are alone." )
      else
        names = []
        objects_near.each { |o| names << o.name }
        m.reply( "#{m.sourcenick}: You see the following objects: #{names.join( ', ' )}." )
      end

      debug "MAP_LENGTH:  #{g.map.map.length}"
      debug "PARTY_POS:   x:#{g.party_pos.x}  y:#{g.party_pos.y}"
      debug "MAP NORTH: #{g.map.at( x, y-1 )}"

      north = g.map.wall?( x, y-1 ) ? "a wall" : "open space"
      east  = g.map.wall?( x+1, y ) ? "a wall" : "open space"
      south = g.map.wall?( x, y+1 ) ? "a wall" : "open space"
      west  = g.map.wall?( x-1, y ) ? "a wall" : "open space"

      m.reply( "In the north is #{north}, east is #{east}, south is #{south}, and in the west you see #{west}." )
    else
      p = nil
      g.objects.each_value { |o| p = o if o.name == params[:object] }
      if p == nil
        m.reply( "#{m.sourcenick}: There is no #{params[:object]} here." )
      else
        m.reply( "#{m.sourcenick}: #{p.description}" )   
      end
    end  
  end


  def handle_go( m, params )
    g = get_game( m )
    return unless spawned?( g, m.sourcenick )

    wall = "Ouch! You bump into a wall."
    x, y = g.party_pos.x, g.party_pos.y
            
    case params[:direction]
      when 'north', 'n'
        if g.map.wall?( x, y-1 )
          m.reply wall 
        else
          g.party_pos.y -= 1
          m.reply "You walk northward."
        end
      when 'east', 'e'
        if g.map.wall?( x+1, y )
          m.reply wall
        else
          g.party_pos.x += 1
          m.reply "You walk eastward."
       end     
      when 'south', 's'
        if g.map.wall?( x, y+1 )
          m.reply wall
        else
          g.party_pos.y += 1  
          m.reply "You walk southward."
        end
      when 'west', 'w'
        if g.map.wall?( x-1, y )
          m.reply wall
        else
          g.party_pos.x -= 1
          m.reply "You walk westward."
        end    
     else
        m.reply( "Go where? Directions: north, east, south, west." )
        return
    end    

    x, y = g.party_pos.x, g.party_pos.y
    g.set_players_pos( x, y )

    p = g.objects[m.sourcenick]
    objects_near = []
    g.objects.each_value { |o| objects_near << o if o.pos == p.pos and o != p }

    unless objects_near.empty?
      m.reply "You encounter a #{o.object_type}!"
    end
  end


  def handle_stats( m, params )
    begin

    g = get_game( m )
    return unless spawned?( g, m.sourcenick )

    p = g.objects[m.sourcenick]
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


