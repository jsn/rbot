# Plugin for the Ruby IRC bot (http://linuxbrit.co.uk/rbot/)
#
# Little IRC game
#
# (c) 2006 Mark Kretschmann <markey@web.de>
# Licensed under GPL V2.
 

class Player

  attr_accessor :hp, :strength

  def initialize
    @hp = 100
    @strength = 10
  end

end


class Monster < Player

  def initialize
    super

  end

end    


class RpgPlugin < Plugin

  def initialize
    super

    @players = Hash.new
  end

#####################################################################
# Core Methods
#####################################################################

  def next_round
  end


  def punch( src_name, dst_name ) 
    src = @players[src_name]
    dst = @players[dst_name]

    damage = rand( src.strength )
    dst.hp -= damage

    @msg.reply( "#{src_name} punches #{dst_name}." )
    @msg.reply( "#{dst_name} loses #{damage} hit points." )
  end

#####################################################################
# Command Handlers
#####################################################################

  def handle_spawn_player( m, params )
    p = Player.new  
    name = m.sourcenick
    @players[name] = p
    m.reply "Player #{name} enters the game."
  end

  def handle_spawn_monster( m, params )
    p = Monster.new  
    name = "grue"
    @players[name] = p
    m.reply "Monster #{name} enters the game."
  end

  def handle_punch( m, params )
    unless @players.has_key?( params[:target] )
      m.reply( "#{m.sourcenick} seems confused: there is noone named #{params[:target]} near.." )
      return
    end
  
    @msg = m  #temp hack
    punch( m.sourcenick, params[:target] )
    next_round
  end

end


plugin = RpgPlugin.new
plugin.register( "rpg" )

plugin.map 'spawn player',  :action => 'handle_spawn_player'
plugin.map 'spawn monster', :action => 'handle_spawn_monster' 
plugin.map 'punch :target', :action => 'handle_punch' 



