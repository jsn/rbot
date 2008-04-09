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
    attr_reader :user
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
    shorts = cards.scan(/[rbgy]\s*(?:\+?\d|[rs])|w\s*(?:\+4)?/)
    debug shorts.inspect
    if shorts.length > 2 or shorts.length < 1
      announce _("you can only play one or two cards")
      return
    end
    if shorts.length == 2 and shorts.first != shorts.last
      announce _("you can only play two cards if they are the same")
      return
    end
    if cards = p.has_card?(shorts.first)
      debug cards
      unless can_play(cards.first)
        announce _("you can't play that card")
        return
      end
      if cards.length >= shorts.length
        set_discard(p.cards.delete_one(cards.shift))
        if shorts.length > 1
          set_discard(p.cards.delete_one(cards.shift))
          announce _("%{p} plays %{card} twice!") % {
            :p => source,
            :card => @discard
          }
        else
          announce _("%{p} plays %{card}") % { :p => source, :card => @discard }
        end
        if p.cards.length == 1
          announce _("%{p} has %{uno}!") % {
            :p => source, :uno => UNO
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
        :p => user, :b => Bold, :n => @picker
      }
      deal(p, @picker)
      @picker = 0
    else
      if @player_has_picked
        announce _("%{p} passes turn") % { :p => user }
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
    return if get_player(user)
    p = Player.new(user)
    @players << p
    deal(p, 7)
    if @join_timer
      @bot.timer.reschedule(@join_timer, 10)
    elsif @players.length > 1
      announce _("game will start in 20 seconds")
      @join_timer = @bot.timer.add_once(20) {
        start_game
      }
    end
  end

  def end_game
    announce _("%{uno} game finished! The winner is %{p}") % {
      :uno => UNO, :p => @players.first
    }
    if @picker > 0
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
    announce _("%{p} wins with %{b}%{score}%{b} points!") % {
        :p => @players.first, :score => score, :b => Bold
    }
    @plugin.end_game(@channel)
  end

end

class UnoPlugin < Plugin
  attr :games
  def initialize
    super
    @games = {}
  end

  def help(plugin, topic="")
    (_("%{uno} game. !uno to start a game. in-game commands (no prefix): ") % {
      :uno => UnoGame::UNO
    }) + [
      _("'jo' to join in"),
      _("'pl <card>' to play <card>"),
      _("'pe' to pick a card"),
      _("'pa' to pass your turn"),
      _("'co <color>' to pick a color"),
      _("'ca' to show current cards"),
      _("'cd' to show the current discard"),
      _("'od' to show the playing order"),
      _("'ti' to show play time"),
      _("'tu' to show whose turn it is")
    ].join(" ; ")
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
          m.reply _("you can't pick a card")
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

  def end_game(channel)
    @games.delete(channel)
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
pg.map 'uno stock', :private => false, :action => :print_stock
pg.default_auth('stock', false)
