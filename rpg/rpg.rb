# Plugin for the Ruby IRC bot (http://linuxbrit.co.uk/rbot/)
#
# Little IRC game
#
# (c) 2006 Mark Kretschmann <markey@web.de>
# Licensed under GPL V2.
 

class Player

  attr_accessor :name, :player_type, :hp, :strength, :description

  def initialize
    @name = ""
    @player_type = "Human"
    @hp = 20
    @strength = 10

    @description = "A typical human geek."
  end


  def attack( g, target ) 
    damage = rand( @strength )
    target.hp -= damage

    if damage > 0 
      g.say( "#{@name} attacks #{target.name}. Hit! (#{damage} HP damage)."  )
    else
      g.say( "#{name} misses." )
    end
  end

end


class Monster < Player

  @@monsters = [] 
 
  def initialize
    super

  end


  def Monster.monsters
    @@monsters
  end
    

  def Monster.register( monster )
    @@monsters << monster
  end


  def act( g )
    g.players.each_value do |p| 
      if p.instance_of?( Player )
        attack( g, p )
      end  
    end
  end

end    


class Orc < Monster
  
  Monster.register Orc

  def initialize
    super

    @name = "orc"
    @player_type = "Orc"
    @hp = 14

    @description = "The Orc is a humanoid creature resembling a caveman. It has dangerous looking fangs and a snout. Somehow, it does not look very smart."
  end

end


class Slime < Monster

  Monster.register Slime

  def initialize
    super

    @name = "slime"
    @player_type = "Slime"
    @hp = 8

    @description = "The Slime is a slimy jelly, oozing over the ground. You really don't feel like touching that." 
  end  

end


class Game

  attr_accessor :channel, :players

  def initialize( channel, bot )
    @channel = channel
    @bot = bot
    @players = Hash.new
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
    "IRC RPG. Commands: 'spawn player', 'spawn monster', 'attack <target>', 'look [object]'."
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
        return
      end
      objects = []
      g.players.each_value { |x| objects << x.name unless x.name == m.sourcenick }
      m.reply( "#{m.sourcenick}: You see the following objects: #{objects.join( ', ' )}." )
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

end
  

plugin = RpgPlugin.new
plugin.register( "rpg" )

plugin.map 'spawn player',   :action => 'handle_spawn_player'
plugin.map 'spawn monster',  :action => 'handle_spawn_monster' 
plugin.map 'attack :target', :action => 'handle_attack' 
plugin.map 'look :object',   :action => 'handle_look',         :defaults => { :object => nil }


