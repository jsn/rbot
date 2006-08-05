
class Creature

  attr_accessor :name, :player_type, :hp, :thac0, :hd, :ac, :description

  def d4( num = 1 )
    result = 0
    num.times { result += rand( 4 ) + 1 }
    result
  end

    
  def d20( num = 1 )
    result = 0
    num.times { result += rand( 20 ) + 1 }
    result
  end

 
  def attack( g, target ) 
    begin

    if d20 < @thac0 - target.ac
      g.say( "#{name} misses." )
      return
    end

    damage = d4( @hd )
    target.hp -= damage
    g.say( "#{@name} attacks #{target.name}. Hit! (#{damage} damage)."  )

    rescue => e
    g.say e.inspect
    end
  end

end
 

class Player < Creature

  attr_accessor :xp

  def initialize
    @name = ""
    @player_type = "Human"
    @hp = 20
    @xp = 0
    @thac0 = 19 
    @hd = 2 
    @ac = 4

    @description = "A typical human geek."
  end

end


class Monster < Creature

  attr_accessor :xp_value
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
    @thac0 = 19
    @ac = 6
    @hd = 1
    @xp_value = 15

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
    @thac0 = 19
    @ac = 5
    @hd = 5
    @xp_value = 60

    @description = "The Slime is a slimy jelly, oozing over the ground. You really don't feel like touching that." 
  end  

end


