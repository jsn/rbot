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
    @legend = { 'O' => Orc, 'S' => Slime, 's' => Sword }

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
|X s O|  |     |
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


class Objects < Array

  def find_by_name( name )
    object = nil
    each do |o|
      if o.name == name
        object = o
        break
      end
    end

    return object
  end

end


class Game

  attr_accessor :channel, :objects, :map, :party_pos

  def initialize( channel, bot )
    @channel = channel
    @bot = bot
    @objects = Objects.new
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
    debug( "set_players_pos(): #{x}  #{y}" )
    @objects.each { |c| c.pos.x, c.pos.y = x, y if c.instance_of?( Player ) }
  end
     

  def spawn( klass, name = nil )
    o = klass.new
    if name
      o.name = name
    end

    objects << o
    return o
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
    "IRC RPG. Commands: 'rpg', 'attack <target>', 'look [object]', 'take <object>', 'inventory', 'stats', 'go <north|n|east|e|south|s|west|w>'."
  end

#####################################################################
# Core Methods
#####################################################################

  # Returns new Game instance for channel, or existing one
  #
  def get_game( m )
      channel = m.replyto

      unless @games.has_key?( channel )
          @games[channel] = Game.new( channel, @bot )
      end

      return @games[channel]
  end


  def schedule( g )
    # Check for death:
    g.objects.each do |p|
      next unless p.kind_of?( Creature )
      if p.hp < 0
        g.say( "#{p.name} dies from his injuries." )
        g.objects.delete( p )        
      end  
    end

    # Let monsters act:
    g.objects.each do |p|
      if p.is_a?( Monster )
        p.act( g )
      end
    end
  end


  def spawned?( g, nick )
    if g.objects.find_by_name( nick )
      return true
    else
      g.say( "You have not joined the game. Use 'rpg' to join." )
      return false  
    end
  end


  def target_spawned?( g, target )
    if g.objects.find_by_name( target )
      return true
    else  
      g.say( "There is noone named #{target} near.." )
      return false
    end
  end


  # Returns an array of objects at the same coordinates as p
  def objects_near( g, p )
    objects = []
    g.objects.each { |o| objects << o if (o.pos == p.pos and o != p) }
    return objects
  end

#####################################################################
# Command Handlers
#####################################################################

  def handle_rpg( m, params )
    g = get_game( m )

    o = g.spawn( Player, m.sourcenick )
    o.pos.x, o.pos.y = g.party_pos.x, g.party_pos.y
    m.reply "Player #{o.name} enters the game."
  end


  def handle_spawn_monster( m, params )
    g = get_game( m )

    o = g.spawn( Monster.monsters[rand( Monster.monsters.length )] ) 
    o.pos.x, o.pos.y = g.party_pos.x, g.party_pos.y
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

    p = g.objects.find_by_name( m.sourcenick )
    x, y = p.pos.x, p.pos.y
    near = objects_near( g, p )

    if params[:object] == nil
      if near.empty?
        m.reply( "#{m.sourcenick}: You are alone." )
      else
        names = []
        near.each { |o| names << o.object_type }
        m.reply( "#{m.sourcenick}: You see the following objects: #{names.join( ', ' )}." )
      end

      debug "MAP_LENGTH:  #{g.map.map.length}"
      debug "PARTY_POS:   x:#{g.party_pos.x}  y:#{g.party_pos.y}"
      debug "PLAYER_POS:  x:#{x}  y:#{y}"
      debug "MAP NORTH: #{g.map.at( x, y-1 )}"

      north = g.map.wall?( x, y-1 ) ? "a wall" : "open space"
      east  = g.map.wall?( x+1, y ) ? "a wall" : "open space"
      south = g.map.wall?( x, y+1 ) ? "a wall" : "open space"
      west  = g.map.wall?( x-1, y ) ? "a wall" : "open space"

      m.reply( "In the north is #{north}, east is #{east}, south is #{south}, and in the west you see #{west}." )
    else
      p = nil
      near.each do |foo|
        if foo.object_type.downcase == params[:object].downcase
          p = foo
          break
        end        
      end
      if p
        m.reply( "#{m.sourcenick}: #{p.description}" )   
      else
        m.reply( "#{m.sourcenick}: There is no #{params[:object]} here." )
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
          str = "You walk northward."
        end
      when 'east', 'e'
        if g.map.wall?( x+1, y )
          m.reply wall
        else
          g.party_pos.x += 1
          str = "You walk eastward."
       end     
      when 'south', 's'
        if g.map.wall?( x, y+1 )
          m.reply wall
        else
          g.party_pos.y += 1  
          str = "You walk southward."
        end
      when 'west', 'w'
        if g.map.wall?( x-1, y )
          m.reply wall
        else
          g.party_pos.x -= 1
          str = "You walk westward."
        end    
     else
        m.reply( "Go where? Directions: north, east, south, west." )
        return
    end    

    x, y = g.party_pos.x, g.party_pos.y
    g.set_players_pos( x, y )

    exits = []
    exits << "north" unless g.map.wall?( x, y-1 )
    exits << "east"  unless g.map.wall?( x+1, y )
    exits << "south" unless g.map.wall?( x, y+1 )
    exits << "west"  unless g.map.wall?( x-1, y )
    str += " (Exits: #{exits.join(', ')})"
    m.reply( str )

    p = g.objects.find_by_name m.sourcenick
    near = objects_near( g, p )

    unless near.empty?
      near.each do |o|
        m.reply "You encounter a #{o.object_type}!"
      end
    end
  end


  def handle_stats( m, params )
    g = get_game( m )
    return unless spawned?( g, m.sourcenick )

    p = g.objects[m.sourcenick]
    m.reply( "Stats for #{m.sourcenick}: HP:#{p.hp}  XP:#{p.xp}  THAC0:#{p.thac0}  AC:#{p.ac}  HD:#{p.hd}" )
  end


  def handle_take( m, params )
    g = get_game( m )
    return unless spawned?( g, m.sourcenick )
    
    p = g.objects.find_by_name m.sourcenick
    near = objects_near( g, p )

    t = nil
    near.each do |foo|
      if foo.object_type.downcase == params[:object].downcase
        t = foo
        break
      end        
    end

    if t == nil
      m.reply "#{m.sourcenick}: There is no #{params[:object]} here."
      return
    end

    if t.kind_of?( Creature )
      m.reply "#{m.sourcenick}: Feeling lonely, eh? You can't take persons."
      return
    end

    t.pos.x, t.pos.y = nil, nil
    p.inventory << t
    m.reply "#{m.sourcenick} picks up a #{t.object_type}."
  end


  def handle_inventory( m, params )
    g = get_game( m )
    return unless spawned?( g, m.sourcenick )
    p = g.objects.find_by_name m.sourcenick

    if p.inventory.empty?
      m.reply "#{m.sourcenick}: You don't carry any objects."
    else
      stuff = []
      p.inventory.each { |i| stuff << i.object_type } 
      m.reply "#{m.sourcenick}: You carry: #{stuff.join(' ')}"
    end
  end

end
  

plugin = RpgPlugin.new
plugin.register( "rpg" )

plugin.map 'rpg',            :action => 'handle_rpg'
plugin.map 'spawn monster',  :action => 'handle_spawn_monster' 
plugin.map 'attack :target', :action => 'handle_attack' 
plugin.map 'look :object',   :action => 'handle_look',         :defaults => { :object => nil }
plugin.map 'go :direction',  :action => 'handle_go' 
plugin.map 'take :object',   :action => 'handle_take'
plugin.map 'stats',          :action => 'handle_stats'
plugin.map 'inventory',      :action => 'handle_inventory'

