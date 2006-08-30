
Position = Struct.new( :x, :y )

class GameObject
  
  attr_accessor :pos, :name, :object_type, :description

  def initialize
    @pos = Position.new( nil, nil )
    @name = ""
    @object_type = ""
    @description = ""
  end
end


class Creature < GameObject

  attr_accessor :state, :hp, :thac0, :hd, :ac, :xp_value, :inventory

  def initialize
    super

    @state = "idle"
    @inventory = []
  end

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
    @state = "fighting"
    target.state = "fighting"

    if d20 < @thac0 - target.ac
      g.say( "#{name} misses." )
      return
    end

    damage = d4( @hd )
    target.hp -= damage

    g.say( "#{@name} attacks #{target.name}. Hit! (#{damage} damage)."  )
  end

end
 

class Player < Creature

  attr_accessor :xp

  def initialize
    super

    @object_type = "Human"
    @hp = 20
    @xp = 0
    @thac0 = 15 
    @hd = 2 
    @ac = 4

    @description = "A typical human geek."
  end


  def attack( g, target )
    super

    if target.hp < 0
      @xp += target.xp_value
      g.say( "#{@name} gains #{target.xp_value} experience points!" ) 
    end
  end

end


class Monster < Creature

  @@monsters = [] 

  def Monster.monsters
    @@monsters
  end
    

  def Monster.register( monster )
    @@monsters << monster
  end


  def act( g )
    case @state
    when "idle"
      return
    when "fighting"
      g.objects.each_value do |o| 
        if o.instance_of?( Player ) and o.pos = @pos
          attack( g, o )
        end  
      end
    end
  end

end    


class Orc < Monster
  
  Monster.register Orc

  def initialize
    super

    @object_type = "Orc"
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

    @object_type = "Slime"
    @hp = 8
    @thac0 = 19
    @ac = 5
    @hd = 5
    @xp_value = 60

    @description = "The Slime is a slimy jelly, oozing over the ground. You really don't feel like touching that." 
  end  

end


class Weapon < GameObject
end


class Sword < Weapon

  def initialize
    super

    @object_type = "Sword"
    @description = "A metal sword"
  end

end

