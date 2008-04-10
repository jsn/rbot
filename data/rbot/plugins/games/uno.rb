#-- vim:sw=2:et
#++
#
# :title: Uno Game Plugin for rbot
#
# Author:: Giuseppe "Oblomov" Bilotta <giuseppe.bilotta@gmail.com>
#
# Copyright:: (C) 2008 Giuseppe Bilotta
#
# License:: GPL v2
#
# Uno Game: get rid of the cards you have
#
# TODO documentation
# TODO allow full form card names for play
# TODO allow color specification with wild
# TODO allow choice of rules re stacking + and playing Reverse with them
# TODO highscore table

class UnoGame
  COLORS = %w{Red Green Blue Yellow}
  SPECIALS = %w{+2 Reverse Skip}
  NUMERICS = (0..9).to_a
  VALUES = NUMERICS + SPECIALS

  def UnoGame.color_map(clr)
    case clr
    when 'Red'
      :red
    when 'Blue'
      :royal_blue
    when 'Green'
      :limegreen
    when 'Yellow'
      :yellow
    end
  end

  def UnoGame.irc_color_bg(clr)
    Irc.color([:white,:black][COLORS.index(clr)%2],UnoGame.color_map(clr))
  end

  def UnoGame.irc_color_fg(clr)
    Irc.color(UnoGame.color_map(clr))
  end

  def UnoGame.colorify(str, fg=false)
    ret = Bold.dup
    str.length.times do |i|
      ret << (fg ?
              UnoGame.irc_color_fg(COLORS[i%4]) :
              UnoGame.irc_color_bg(COLORS[i%4]) ) +str[i,1]
    end
    ret << NormalText
  end

  UNO = UnoGame.colorify('UNO!', true)

  # Colored play cards
  class Card
    attr_reader :color
    attr_reader :value
    attr_reader :shortform
    attr_reader :to_s
    attr_reader :score

    def initialize(color, value)
      raise unless COLORS.include? color
      @color = color.dup
      raise unless VALUES.include? value
      if NUMERICS.include? value
        @value = value
        @score = value
      else
        @value = value.dup
        @score = 20
      end
      if @value == '+2'
        @shortform = (@color[0,1]+@value).downcase
      else
        @shortform = (@color[0,1]+@value.to_s[0,1]).downcase
      end
      @to_s = UnoGame.irc_color_bg(@color) +
        Bold + ['', @color, @value, ''].join(' ') + NormalText
    end

    def picker
      return 0 unless @value.to_s[0,1] == '+'
      return @value[1,1].to_i
    end

    def special?
      SPECIALS.include?(@value)
    end

    def <=>(other)
      cc = self.color <=> other.color
      if cc == 0
        return self.value.to_s <=> other.value.to_s
      else
        return cc
      end
    end
    include Comparable
  end

  # Wild, Wild +4 cards
  class Wild < Card
    def initialize(value=nil)
      @color = 'Wild'
      raise if value and not value == '+4'
      if value
        @value = value.dup 
        @shortform = 'w'+value
      else
        @value = nil
        @shortform = 'w'
      end
      @score = 50
      @to_s = UnoGame.colorify(['', @color, @value, ''].compact.join(' '))
    end
    def special?
      @value
    end
  end

  class Player
    attr_accessor :cards
    attr_accessor :user
    def initialize(user)
      @user = user
      @cards = []
    end
    def has_card?(short)
      has = []
      @cards.each { |c|
        has << c if c.shortform == short
      }
      if has.empty?
        return false
      else
        return has
      end
    end
    def to_s
      Bold + @user.to_s + Bold
    end
  end

  attr_reader :stock
  attr_reader :discard
  attr_reader :channel
  attr :players
  attr_reader :player_has_picked
  attr_reader :picker

  def initialize(plugin, channel)
    @channel = channel
    @plugin = plugin
    @bot = plugin.bot
    @players = []
    @dropouts = []
    @discard = nil
    make_base_stock
    @stock = []
    make_stock
    @start_time = nil
    @join_timer = nil
  end

  def get_player(user)
    @players.each { |p| return p if p.user == user }
    return nil
  end

  def announce(msg, opts={})
    @bot.say channel, msg, opts
  end

  def notify(player, msg, opts={})
    @bot.notice player.user, msg, opts
  end

  def make_base_stock
    @base_stock = COLORS.inject([]) do |list, clr|
      VALUES.each do |n|
        list << Card.new(clr, n)
        list << Card.new(clr, n) unless n == 0
      end
      list
    end
    4.times do
      @base_stock << Wild.new
      @base_stock << Wild.new('+4')
    end
  end

  def make_stock
    @stock.replace @base_stock
    # remove the cards in the players hand
    @players.each { |p| p.cards.each { |c| @stock.delete_one c } }
    # remove current top discarded card if present
    if @discard
      @stock.delete_one(discard)
    end
    @stock.shuffle!
  end

  def start_game
    debug "Starting game"
    @players.shuffle!
    show_order
    announce _("%{p} deals the first card from the stock") % {
      :p => @players.first
    }
    card = @stock.shift
    @picker = 0
    @special = false
    while Wild === card do
      @stock.insert(rand(@stock.length), card)
      card = @stock.shift
    end
    set_discard(card)
    show_discard
    if @special
      do_special
    end
    next_turn
    @start_time = Time.now
  end

  def reverse_turn
    if @players.length > 2
      @players.reverse!
      # put the current player back in its place
      @players.unshift @players.pop
      announce _("Playing order was reversed!")
    else
      skip_turn
    end
  end

  def skip_turn
    @players << @players.shift
    announce _("%{p} skips a turn!") % {
      # this is first and not last because the actual
      # turn change will be done by the following next_turn
      :p => @players.first
    }
  end

  def do_special
    case @discard.value
    when 'Reverse'
      reverse_turn
      @special = false
    when 'Skip'
      skip_turn
      @special = false
    end
  end

  def set_discard(card)
    @discard = card
    @value = card.value.dup rescue card.value
    if Wild === card
      @color = nil
    else
      @color = card.color.dup
    end
    if card.picker > 0
      @picker += card.picker
      @last_picker = @discard.picker
    end
    if card.special?
      @special = true
    else
      @special = false
    end
  end

  def next_turn(opts={})
    @players << @players.shift
    @player_has_picked = false
    show_turn
  end

  def can_play(card)
    # When a +something is online, you can only play
    # a +something of same or higher something, or a Reverse of
    # the correct color
    # TODO make optional
    if @picker > 0
      if (card.value == 'Reverse' and card.color == @color) or card.picker >= @last_picker
        return true
      else
        return false
      end
    else
      # You can always play a Wild
      # FIXME W+4 can only be played if you don't have a proper card
      # TODO make it playable anyway, and allow players to challenge
      return true if Wild === card
      # On a Wild, you must match the color
      if Wild === @discard
        return card.color == @color
      else
        # Otherwise, you can match either the value or the color
        return (card.value == @value) || (card.color == @color)
      end
    end
  end

  def play_card(source, cards)
    debug "Playing card #{cards}"
    p = get_player(source)
    shorts = cards.gsub(/\s+/,'').match(/^(?:([rbgy]\d){1,2}|([rbgy](?:\+\d|[rs]))|(w(?:\+4)?)([rbgy])?)$/).to_a
    debug shorts.inspect
    if shorts.empty?
      announce _("what cards were that again?")
      return
    end
    full = shorts[0]
    short = shorts[1] || shorts[2] || shorts[3]
    jolly = shorts[3]
    jcolor = shorts[4]
    if jolly
      toplay = 1
    else
      toplay = (full == short) ? 1 : 2
    end
    debug [full, short, jolly, jcolor, toplay].inspect
    # r7r7 -> r7r7, r7, nil, nil
    # r7 -> r7, r7, nil, nil
    # w -> w, nil, w, nil
    # wg -> wg, nil, w, g
    if cards = p.has_card?(short)
      debug cards
      unless can_play(cards.first)
        announce _("you can't play that card")
        return
      end
      if cards.length >= toplay
        set_discard(p.cards.delete_one(cards.shift))
        if toplay > 1
          set_discard(p.cards.delete_one(cards.shift))
          announce _("%{p} plays %{card} twice!") % {
            :p => p,
            :card => @discard
          }
        else
          announce _("%{p} plays %{card}") % { :p => p, :card => @discard }
        end
        if p.cards.length == 1
          announce _("%{p} has %{uno}!") % {
            :p => p, :uno => UNO
          }
        elsif p.cards.length == 0
          end_game
          return
        end
        show_picker
        if @color
          if @special
            do_special
          end
          next_turn
        elsif jcolor
          choose_color(p.user, jcolor)
        else
          announce _("%{p}, choose a color with: co r|b|g|y") % { :p => p }
        end
      else
        announce _("you don't have two cards of that kind")
      end
    else
      announce _("you don't have that card")
    end
  end

  def pass(user)
    p = get_player(user)
    if @picker > 0
      announce _("%{p} passes turn, and has to pick %{b}%{n}%{b} cards!") % {
        :p => p, :b => Bold, :n => @picker
      }
      deal(p, @picker)
      @picker = 0
    else
      if @player_has_picked
        announce _("%{p} passes turn") % { :p => p }
      else
        announce _("you need to pick a card first")
        return
      end
    end
    next_turn
  end

  def choose_color(user, color)
    case color
    when 'r'
      @color = 'Red'
    when 'b'
      @color = 'Blue'
    when 'g'
      @color = 'Green'
    when 'y'
      @color = 'Yellow'
    else
      announce _('what color is that?')
      return
    end
    announce _('color is now %{c}') % {
      :c => UnoGame.irc_color_bg(@color)+" #{@color} "
    }
    next_turn
  end

  def show_time
    if @start_time
      announce _("This %{uno} game has been going on for %{time}") % {
        :uno => UNO,
        :time => Utils.secs_to_string(Time.now - @start_time)
      }
    else
      announce _("The game hasn't started yet")
    end
  end

  def show_order
    announce _("%{uno} playing turn: %{players}") % {
      :uno => UNO, :players => players.join(' ')
    }
  end

  def show_turn(opts={})
    cards = true
    cards = opts[:cards] if opts.key?(:cards)
    player = @players.first
    announce _("it's %{player}'s turn") % { :player => player }
    show_user_cards(player) if cards
  end

  def has_turn?(source)
    @players.first.user == source
  end

  def show_picker
    if @picker > 0
      announce _("next player must respond correctly or pick %{b}%{n}%{b} cards") % {
        :b => Bold, :n => @picker
      }
    end
  end

  def show_discard
    announce _("Current discard: %{card} %{c}") % { :card => @discard,
      :c => (Wild === @discard) ? UnoGame.irc_color_bg(@color) + " #{@color} " : nil
    }
    show_picker
  end

  def show_user_cards(player)
    p = Player === player ? player : get_player(player)
    notify p, _('Your cards: %{cards}') % {
      :cards => p.cards.join(' ')
    }
  end

  def show_all_cards(u=nil)
    announce(@players.inject([]) { |list, p|
      list << [p, p.cards.length].join(': ')
    }.join(', '))
    if u
      show_user_cards(u)
    end
  end

  def pick_card(user)
    p = get_player(user)
    announce _("%{player} picks a card") % { :player => p }
    deal(p, 1)
    @player_has_picked = true
  end

  def deal(player, num=1)
    picked = []
    num.times do
      picked << @stock.delete_one
      if @stock.length == 0
        announce _("Shuffling discarded cards")
        make_stock
        if @stock.length == 0
          announce _("No more cards!")
          end_game # FIXME nope!
        end
      end
    end
    picked.sort!
    notify player, _("You picked %{picked}") % { :picked => picked.join(' ') }
    player.cards += picked
    player.cards.sort!
  end

  def add_player(user)
    if p = get_player(user)
      announce _("you're already in the game, %{p}") % {
        :p => p
      }
      return
    end
    @dropouts.each do |dp|
      if dp.user == user
        announce _("you dropped from the game, %{p}, you can't get back in") % {
          :p => dp
        }
        return
      end
    end
    cards = 7
    if @start_time
      cards = @players.inject(0) do |s, pl|
        s +=pl.cards.length
      end/@players.length
    end
    p = Player.new(user)
    @players << p
    announce _("%{p} joins this game of %{uno}") % {
      :p => p, :uno => UNO
    }
    deal(p, cards)
    return if @start_time
    if @join_timer
      @bot.timer.reschedule(@join_timer, 10)
    elsif @players.length > 1
      announce _("game will start in 20 seconds")
      @join_timer = @bot.timer.add_once(20) {
        start_game
      }
    end
  end

  def drop_player(user)
    unless p = get_player(user)
      announce _("%{p} isn't playing %{uno}") % {
        :p => p, :uno => UNO
      }
      return
    end
    announce _("%{p} gives up this game of %{uno}") % {
      :p => p, :uno => UNO
    }
    if @players.length == 2
      if p == @players.first
        next_turn
      end
      end_game
      return
    end
    debug @stock.length
    while p.cards.length > 0
      @stock.insert(rand(@stock.length), p.cards.shift)
    end
    debug @stock.length
    @dropouts << @players.delete_one(p)
  end

  def replace_player(old, new)
    # The new user
    user = channel.get_user(new)
    if p = get_player(user)
      announce _("%{p} is already playing %{uno} here") % {
        :p => p, :uno => UNO
      }
      return
    end
    # We scan the player list of the player with the old nick, instead
    # of using get_player, in case of IRC drops etc
    @players.each do |p|
      if p.user.nick == old
        p.user = user
        announce _("%{p} takes %{b}%{old}%{b}'s place at %{uno}") % {
          :p => p, :b => Bold, :old => old, :uno => UNO
        }
        return
      end
    end
    announce _("%{b}%{old}%{b} isn't playing %{uno} here") % {
      :uno => UNO, :b => Bold, :old => old
    }
  end

  def end_game(halted = false)
    if halted
      announce _("%{uno} game halted after %{time}") % {
        :time => Utils.secs_to_string(Time.now-@start_time),
        :uno => UNO
      }
    else
      announce _("%{uno} game finished after %{time}! The winner is %{p}") % {
        :time => Utils.secs_to_string(Time.now-@start_time),
        :uno => UNO, :p => @players.first
      }
    end
    if @picker > 0 and not halted
      p = @players[1]
      announce _("%{p} has to pick %{b}%{n}%{b} cards!") % {
        :p => p, :n => @picker, :b => Bold
      }
      deal(p, @picker)
      @picker = 0
    end
    score = @players.inject(0) do |sum, p|
      if p.cards.length > 0
        announce _("%{p} still had %{cards}") % {
          :p => p, :cards => p.cards.join(' ')
        }
        sum += p.cards.inject(0) do |cs, c|
          cs += c.score
        end
      end
      sum
    end
    if not halted
      announce _("%{p} wins with %{b}%{score}%{b} points!") % {
        :p => @players.first, :score => score, :b => Bold
      }
    end
    @plugin.do_end_game(@channel)
  end

end

class UnoPlugin < Plugin
  attr :games
  def initialize
    super
    @games = {}
  end

  def help(plugin, topic="")
    case topic
    when 'commands'
      [
      _("'jo' to join in"),
      _("'pl <card>' to play <card>: e.g. 'pl g7' to play Green 7, or 'pl rr' to play Red Reverse, or 'pl y2y2' to play both Yellow 2 cards"),
      _("'pe' to pick a card"),
      _("'pa' to pass your turn"),
      _("'co <color>' to pick a color after playing a Wild: e.g. 'co g' to select Green (or 'pl w+4 g' to select the color when playing the Wild)"),
      _("'ca' to show current cards"),
      _("'cd' to show the current discard"),
      _("'od' to show the playing order"),
      _("'ti' to show play time"),
      _("'tu' to show whose turn it is")
    ].join(" ; ")
    when 'rules'
      _("play all your cards, one at a time, by matching either the color or the value of the currently discarded card. ") +
      _("cards with special effects: Skip (next player skips a turn), Reverse (reverses the playing order), +2 (next player has to take 2 cards). ") +
      _("Wilds can be played on any card, and you must specify the color for the next card. ") +
      _("Wild +4 also forces the next player to take 4 cards, but it can only be played if you can't play a color card. ") +
      _("you can play another +2 or +4 card on a +2 card, and a +4 on a +4, forcing the first player who can't play one to pick the cumulative sum of all cards. ") +
      _("you can also play a Reverse on a +2 or +4, bouncing the effect back to the previous player (that now comes next). ")
    else
      (_("%{uno} game. !uno to start a game. see help uno rules for the rules. commands: %{cmds}") % {
        :uno => UnoGame::UNO,
        :cmds => help(plugin, 'commands')
      })
    end
  end

  def message(m)
    return unless @games.key?(m.channel)
    g = @games[m.channel]
    case m.plugin.intern
    when :jo # join game
      return if m.params
      g.add_player(m.source)
    when :pe # pick card
      return if m.params
      if g.has_turn?(m.source)
        if g.player_has_picked
          m.reply _("you already picked a card")
        elsif g.picker > 0
          g.pass(m.source)
        else
          g.pick_card(m.source)
        end
      else
        m.reply _("It's not your turn")
      end
    when :pa # pass turn
      return if m.params
      if g.has_turn?(m.source)
        g.pass(m.source)
      else
        m.reply _("It's not your turn")
      end
    when :pl # play card
      if g.has_turn?(m.source)
        g.play_card(m.source, m.params.downcase)
      else
        m.reply _("It's not your turn")
      end
    when :co # pick color
      if g.has_turn?(m.source)
        g.choose_color(m.source, m.params.downcase)
      else
        m.reply _("It's not your turn")
      end
    when :ca # show current cards
      return if m.params
      g.show_all_cards(m.source)
    when :cd # show current discard
      return if m.params
      g.show_discard
    # TODO
    # when :ch
    #   g.challenge
    when :od # show playing order
      return if m.params
      g.show_order
    when :ti # show play time
      return if m.params
      g.show_time
    when :tu # show whose turn is it
      return if m.params
      if g.has_turn?(m.source)
        m.nickreply _("it's your turn, sleepyhead")
      else
        g.show_turn(:cards => false)
      end
    end
  end

  def create_game(m, p)
    if @games.key?(m.channel)
      m.reply _("There is already an %{uno} game running here, say 'jo' to join in") % { :uno => UnoGame::UNO }
      return
    end
    @games[m.channel] = UnoGame.new(self, m.channel)
    m.reply _("Ok, created %{uno} game on %{channel}, say 'jo' to join in") % {
      :uno => UnoGame::UNO,
      :channel => m.channel
    }
  end

  def end_game(m, p)
    unless @games.key?(m.channel)
      m.reply _("There is no %{uno} game running here") % { :uno => UnoGame::UNO }
      return
    end
    @games[m.channel].end_game(true)
  end

  def do_end_game(channel)
    @games.delete(channel)
  end

  def replace_player(m, p)
    unless @games.key?(m.channel)
      m.reply _("There is no %{uno} game running here") % { :uno => UnoGame::UNO }
      return
    end
    @games[m.channel].replace_player(p[:old], p[:new])
  end

  def drop_player(m, p)
    unless @games.key?(m.channel)
      m.reply _("There is no %{uno} game running here") % { :uno => UnoGame::UNO }
      return
    end
    who = p[:nick] ? m.channel.get_user(p[:nick]) : m.source
    @games[m.channel].drop_player(who)
  end

  def print_stock(m, p)
    unless @games.key?(m.channel)
      m.reply _("There is no %{uno} game running here") % { :uno => UnoGame::UNO }
      return
    end
    stock = @games[m.channel].stock
    m.reply(_("%{num} cards in stock: %{stock}") % {
      :num => stock.length,
      :stock => stock.join(' ')
    }, :split_at => /#{NormalText}\s*/)
  end
end

pg = UnoPlugin.new

pg.map 'uno', :private => false, :action => :create_game
pg.map 'uno end', :private => false, :action => :end_game
pg.map 'uno drop', :private => false, :action => :drop_player
pg.map 'uno giveup', :private => false, :action => :drop_player
pg.map 'uno drop :nick', :private => false, :action => :drop_player, :auth_path => ':other'
pg.map 'uno replace :old [with] :new', :private => false, :action => :replace_player
pg.map 'uno stock', :private => false, :action => :print_stock

pg.default_auth('stock', false)
pg.default_auth('end', false)
pg.default_auth('drop::other', false)
pg.default_auth('replace', false)
