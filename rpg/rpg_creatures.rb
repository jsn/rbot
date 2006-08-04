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


