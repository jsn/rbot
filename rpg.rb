# Plugin for the Ruby IRC bot (http://linuxbrit.co.uk/rbot/)
#
# Little IRC game
#
# (c) 2006 Mark Kretschmann <markey@web.de>
# Licensed under GPL V2.
 

class Player

  attr_accessor :name, :hp, :strength

  def initialize
    @name = ""
    @hp = 20
    @strength = 10
  end


  def punch( game, target ) 
    damage = rand( @strength )
    target.hp -= damage

    game.msg.reply( "#{@name} punches #{target.name}." )
    game.msg.reply( "#{target.name} loses #{damage} hit points." )
  end

end


class Monster < Player

  def initialize
    super
  end


  def act( game )
    game.players.each_value do |p| 
      if p.instance_of?( Player )
        punch( game, p )
      end  
    end
  end

end    


class RpgPlugin < Plugin

  attr_accessor :players, :msg

  def initialize
    super

    @players = Hash.new
  end

#####################################################################
# Core Methods
#####################################################################

  def schedule
    # Check for death:
    @players.each_value do |p|
      if p.hp < 0
        @msg.reply( "#{p.name} dies from his injuries :(" )
        @players.delete( p.name )        
      end  
    end

    # Let monsters act:
    @players.each_value do |p|
      if p.instance_of?( Monster )
        p.act( self )
      end
    end
  end


  def spawned?( m, nick )
    if @players.has_key?( nick )
      return true
    else
      m.reply( "You have not joined the game. Use 'spawn player' to join." )
      return false  
    end
  end


  def target_spawned?( m, target )
    if @players.has_key?( target )
      return true
    else  
      m.reply( "#{m.sourcenick} seems confused: there is noone named #{target} near.." )
      return false
    end
  end
 

#####################################################################
# Command Handlers
#####################################################################

  def handle_spawn_player( m, params )
    p = Player.new  
    p.name = m.sourcenick
    @players[p.name] = p
    m.reply "Player #{p.name} enters the game."

    handle_spawn_monster m, params  # for testing
  end


  def handle_spawn_monster( m, params )
    p = Monster.new  
    p.name = "grue"
    @players[p.name] = p
    m.reply "Monster #{p.name} enters the game."
  end


  def handle_punch( m, params )
    return unless spawned?( m, m.sourcenick )
    return unless target_spawned?( m, params[:target] )
 
    @msg = m  #temp hack
    @players[m.sourcenick].punch( self, @players[params[:target]] )
    schedule
  end

end


plugin = RpgPlugin.new
plugin.register( "rpg" )

plugin.map 'spawn player',  :action => 'handle_spawn_player'
plugin.map 'spawn monster', :action => 'handle_spawn_monster' 
plugin.map 'punch :target', :action => 'handle_punch' 


