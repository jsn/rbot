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
# TODO allow choice of rules re stacking + and playing Reverse with them

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

  # cards in stock
  attr_reader :stock
  # current discard
  attr_reader :discard
  # previous discard, in case of challenge
  attr_reader :last_discard
  # channel the game is played in
  attr_reader :channel
  # list of players
  attr :players
  # true if the player picked a card (and can thus pass turn)
  attr_reader :player_has_picked
  # number of cards to be picked if the player can't play an appropriate card
  attr_reader :picker

  # game start time
  attr :start_time

  # the IRC user that created the game
  attr_accessor :manager

  def initialize(plugin, channel, manager)
    @channel = channel
    @plugin = plugin
    @bot = plugin.bot
    @players = []
    @dropouts = []
    @discard = nil
    @last_discard = nil
    @value = nil
    @color = nil
    make_base_stock
    @stock = []
    make_stock
    @start_time = nil
    @join_timer = nil
    @picker = 0
    @last_picker = 0
    @must_play = nil
    @manager = manager
  end

  def get_player(user)
    case user
    when User
      @players.each do |p|
        return p if p.user == user
      end
    when String
      @players.each do |p|
        return p if p.user.irc_downcase == user.irc_downcase(channel.casemap)
      end
    else
      get_player(user.to_s)
    end
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

  def elapsed_time
    if @start_time
      Utils.secs_to_string(Time.now-@start_time)
    else
      _("no time")
    end
  end

  def reverse_turn
    # if there are two players, the Reverse acts like a Skip, unless
    # there's a @picker running, in which case the Reverse should bounce the
    # pick on the other player
    if @players.length > 2
      @players.reverse!
      # put the current player back in its place
      @players.unshift @players.pop
      announce _("Playing order was reversed!")
    elsif @picker > 0
      announce _("%{cp} bounces the pick to %{np}") % {
        :cp => @players.first,
        :np => @players.last
      }
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
    @must_play = nil
  end

  def next_turn(opts={})
    @players << @players.shift
    @player_has_picked = false
    show_turn
  end

  def can_play(card)
    # if play is forced, check against the only allowed cards
    return false if @must_play and not @must_play.include?(card)

    # When a +something is online, you can only play a +something of same or
    # higher something, or a Reverse of the correct color, or a Reverse on
    # a Reverse
    # TODO make optional
    if @picker > 0
      return true if card.picker >= @last_picker
      return true if card.value == 'Reverse' and (card.color == @color or @discard.value == card.value)
      return false
    else
      # You can always play a Wild
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
    shorts = cards.gsub(/\s+/,'').match(/^(?:([rbgy]\+?\d){1,2}|([rbgy][rs])|(w(?:\+4)?)([rbgy])?)$/).to_a
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
        # if the played card is a W+4 not played during a stacking +x
        # TODO if A plays an illegal W+4, B plays a W+4, should the next
        # player be able to challenge A? For the time being we say no,
        # but I think he should, and in case A's move was illegal
        # game would have to go back, A would get the penalty and replay,
        # while if it was legal the challenger would get 50% more cards,
        # i.e. 12 cards (or more if the stacked +4 were more). This would
        # only be possible if the first W+4 was illegal, so it wouldn't
        # apply for a W+4 played on a +2 anyway.
        #
        if @picker == 0 and Wild === cards.first and cards.first.value 
          # save the previous discard in case of challenge
          @last_discard = @discard.dup
          # save the color too, in case it was a Wild
          @last_color = @color.dup
        else
          # mark the move as not challengeable
          @last_discard = nil
          @last_color = nil
        end
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

  def challenge
    return unless @last_discard
    # current player
    cp = @players.first
    # previous player
    lp = @players.last
    announce _("%{cp} challenges %{lp}'s %{card}!") % {
      :cp => cp, :lp => lp, :card => @discard
    }
    # show the cards of the previous player to the current player
    notify cp, _("%{p} has %{cards}") % {
      :p => lp, :cards => lp.cards.join(' ')
    }
    # check if the previous player had a non-special card of the correct color
    legal = true
    lp.cards.each do |c|
      if c.color == @last_color and not c.special?
        legal = false
      end
    end
    if legal
      @picker += 2
      announce _("%{lp}'s move was legal, %{cp} must pick %{b}%{n}%{b} cards!") % {
        :cp => cp, :lp => lp, :b => Bold, :n => @picker
      }
      @last_color = nil
      @last_discard = nil
      deal(cp, @picker)
      @picker = 0
      next_turn
    else
      announce _("%{lp}'s move was %{b}not%{b} legal, %{lp} must pick %{b}%{n}%{b} cards and play again!") % {
        :cp => cp, :lp => lp, :b => Bold, :n => @picker
      }
      lp.cards << @discard # put the W+4 back in place

      # reset the discard
      @color = @last_color.dup
      @discard = @last_discard.dup
      @special = false
      @value = @discard.value.dup rescue @discard.value
      @last_color = nil
      @last_discard = nil

      # force the player to play the current cards
      @must_play = lp.cards.dup

      # give him the penalty cards
      deal(lp, @picker)
      @picker = 0

      # and restore the turn
      @players.unshift @players.pop
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
    # you can only pick a color if the current color is unset
    if @color
      announce _("you can't pick a color now, %{p}") % {
        :p => get_player(user)
      }
      return
    end
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
        :time => elapsed_time
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
    @start_time && (@players.first.user == source)
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
    return unless p
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
      cards = (@players.inject(0) do |s, pl|
        s +=pl.cards.length
      end*1.0/@players.length).ceil
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

  def drop_player(nick)
    # A nick is passed because the original player might have left
    # the channel or IRC
    unless p = get_player(nick)
      announce _("%{p} isn't playing %{uno}") % {
        :p => p, :uno => UNO
      }
      return
    end
    announce _("%{p} gives up this game of %{uno}") % {
      :p => p, :uno => UNO
    }
    case @players.length
    when 2
      if p == @players.first
        next_turn
      end
      end_game
      return
    when 1
      end_game(true)
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
    runtime = @start_time ? Time.now -  @start_time : 0
    if halted
      if @start_time
        announce _("%{uno} game halted after %{time}") % {
          :time => elapsed_time,
          :uno => UNO
        }
      else
        announce _("%{uno} game halted before it could start") % {
          :uno => UNO
        }
      end
    else
      announce _("%{uno} game finished after %{time}! The winner is %{p}") % {
        :time => elapsed_time,
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

    closure = { :dropouts => @dropouts, :players => @players, :runtime => runtime }
    if not halted
      announce _("%{p} wins with %{b}%{score}%{b} points!") % {
        :p => @players.first, :score => score, :b => Bold
      }
      closure.merge!(:winner => @players.first, :score => score,
        :opponents => @players.length - 1)
    end

    @plugin.do_end_game(@channel, closure)
  end

end

# A won game: store score and number of opponents, so we can calculate
# an average score per opponent (requested by Squiddhartha)
define_structure :UnoGameWon, :score, :opponents
# For each player we store the number of games played, the number of
# games forfeited, and an UnoGameWon for each won game
define_structure :UnoPlayerStats, :played, :forfeits, :won

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
      _("'ch' to challenge a Wild +4"),
      _("'od' to show the playing order"),
      _("'ti' to show play time"),
      _("'tu' to show whose turn it is")
    ].join("; ")
    when 'challenge'
      _("A Wild +4 can only be played legally if you don't have normal (not special) cards of the current color. ") +
      _("The next player can challenge a W+4 by using the 'ch' command. ") +
      _("If the W+4 play was illegal, the player who played it must pick the W+4, pick 4 cards from the stock, and play a legal card. ") +
      _("If the W+4 play was legal, the challenger must pick 6 cards instead of 4.")
    when 'rules'
      _("play all your cards, one at a time, by matching either the color or the value of the currently discarded card. ") +
      _("cards with special effects: Skip (next player skips a turn), Reverse (reverses the playing order), +2 (next player has to take 2 cards). ") +
      _("Wilds can be played on any card, and you must specify the color for the next card. ") +
      _("Wild +4 also forces the next player to take 4 cards, but it can only be played if you can't play a color card. ") +
      _("you can play another +2 or +4 card on a +2 card, and a +4 on a +4, forcing the first player who can't play one to pick the cumulative sum of all cards. ") +
      _("you can also play a Reverse on a +2 or +4, bouncing the effect back to the previous player (that now comes next). ")
    when /scor(?:e|ing)/, /points?/
      [
      _("The points won with a game of %{uno} are totalled from the cards remaining in the hands of the other players."),
      _("Each normal (not special) card is worth its face value (from 0 to 9 points)."),
      _("Each colored special card (+2, Reverse, Skip) is worth 20 points."),
      _("Each Wild and Wild +4 is worth 50 points.")
      ].join(" ") % { :uno => UnoGame::UNO }
    when /cards?/
      [
      _("There are 108 cards in a standard %{uno} deck."),
      _("For each color (Blue, Green, Red, Yellow) there are 19 numbered cards (from 0 to 9), with two of each number except for 0."),
      _("There are also 6 special cards for each color, two each of +2, Reverse, Skip."),
      _("Finally, there are 4 Wild and 4 Wild +4 cards.")
      ].join(" ") % { :uno => UnoGame::UNO }
    when 'admin'
      _("The game manager (the user that started the game) can execute the following commands to manage it: ") +
      [
      _("'uno drop <user>' to drop a user from the game (any user can drop itself using 'uno drop')"),
      _("'uno replace <old> [with] <new>' to replace a player with someone else (useful in case of disconnects)"),
      _("'uno transfer [to] <nick>' to transfer game ownership to someone else"),
      _("'uno end' to end the game before its natural completion")
      ].join("; ")
    else
      _("%{uno} game. !uno to start a game. see 'help uno rules' for the rules, 'help uno admin' for admin commands. In-game commands: %{cmds}.") % {
        :uno => UnoGame::UNO,
        :cmds => help(plugin, 'commands')
      }
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
      return if m.params or not g.start_time
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
      return if m.params or not g.start_time
      g.show_discard
    when :ch
      if g.has_turn?(m.source)
        if g.last_discard
          g.challenge
        else
          m.reply _("previous move cannot be challenged")
        end
      else
        m.reply _("It's not your turn")
      end
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
      m.reply _("There is already an %{uno} game running here, managed by %{who}. say 'jo' to join in") % {
        :who => @games[m.channel].manager,
        :uno => UnoGame::UNO
      }
      return
    end
    @games[m.channel] = UnoGame.new(self, m.channel, m.source)
    @bot.auth.irc_to_botuser(m.source).set_temp_permission('uno::manage', true, m.channel)
    m.reply _("Ok, created %{uno} game on %{channel}, say 'jo' to join in") % {
      :uno => UnoGame::UNO,
      :channel => m.channel
    }
  end

  def transfer_ownership(m, p)
    unless @games.key?(m.channel)
      m.reply _("There is no %{uno} game running here") % { :uno => UnoGame::UNO }
      return
    end
    g = @games[m.channel]
    old = g.manager
    new = m.channel.get_user(p[:nick])
    if new
      g.manager = new
      @bot.auth.irc_to_botuser(old).reset_temp_permission('uno::manage', m.channel)
      @bot.auth.irc_to_botuser(new).set_temp_permission('uno::manage', true, m.channel)
      m.reply _("%{uno} game ownership transferred from %{old} to %{nick}") % {
        :uno => UnoGame::UNO, :old => old, :nick => p[:nick]
      }
    else
      m.reply _("who is this %{nick} you want me to transfer game ownership to?") % p
    end
  end

  def end_game(m, p)
    unless @games.key?(m.channel)
      m.reply _("There is no %{uno} game running here") % { :uno => UnoGame::UNO }
      return
    end
    @games[m.channel].end_game(true)
  end

  def cleanup
    @games.each { |k, g| g.end_game(true) }
    super
  end

  def chan_reg(channel)
    @registry.sub_registry(channel.downcase)
  end

  def chan_stats(channel)
    stats = chan_reg(channel).sub_registry('stats')
    class << stats
      def store(val)
        val.to_i
      end
      def restore(val)
        val.to_i
      end
    end
    stats.set_default(0)
    return stats
  end

  def chan_pstats(channel)
    pstats = chan_reg(channel).sub_registry('players')
    pstats.set_default(UnoPlayerStats.new(0,0,[]))
    return pstats
  end

  def do_end_game(channel, closure)
    reg = chan_reg(channel)
    stats = chan_stats(channel)
    stats['played'] += 1
    stats['played_runtime'] += closure[:runtime]
    if closure[:winner]
      stats['finished'] += 1
      stats['finished_runtime'] += closure[:runtime]

      pstats = chan_pstats(channel)

      closure[:players].each do |pl|
        k = pl.user.downcase
        pls = pstats[k]
        pls.played += 1
        pstats[k] = pls
      end

      closure[:dropouts].each do |pl|
        k = pl.user.downcase
        pls = pstats[k]
        pls.played += 1
        pls.forfeits += 1
        pstats[k] = pls
      end

      winner = closure[:winner]
      won = UnoGameWon.new(closure[:score], closure[:opponents])
      k = winner.user.downcase
      pls = pstats[k] # already marked played +1 above
      pls.won << won
      pstats[k] = pls
    end

    @bot.auth.irc_to_botuser(@games[channel].manager).reset_temp_permission('uno::manage', channel)
    @games.delete(channel)
  end

  def do_chanstats(m, p)
    stats = chan_stats(m.channel)
    np = stats['played']
    nf = stats['finished']
    if np > 0
      str = _("%{nf} %{uno} games completed over %{np} games played. ") % {
        :np => np, :uno => UnoGame::UNO, :nf => nf
      }
      cgt = stats['finished_runtime']
      tgt = stats['played_runtime']
      str << _("%{cgt} game time for completed games") % {
        :cgt => Utils.secs_to_string(cgt)
      }
      if np > nf
        str << _(" on %{tgt} total game time. ") % {
          :tgt => Utils.secs_to_string(tgt)
        }
      else
        str << ". "
      end
      str << _("%{avg} average game time for completed games") % {
        :avg => Utils.secs_to_string(cgt/nf)
      }
      str << _(", %{tavg} for all games") % {
        :tavg => Utils.secs_to_string(tgt/np)
      } if np > nf
      m.reply str
    else
      m.reply _("nobody has played %{uno} on %{chan} yet") % {
        :uno => UnoGame::UNO, :chan => m.channel
      }
    end
  end

  def do_pstats(m, p)
    dnick = p[:nick] || m.source # display-nick, don't later case
    nick = dnick.downcase
    ps = chan_pstats(m.channel)[nick]
    if ps.played == 0
      m.reply _("%{nick} never played %{uno} here") % {
        :uno => UnoGame::UNO, :nick => dnick
      }
      return
    end
    np = ps.played
    nf = ps.forfeits
    nw = ps.won.length
    score = ps.won.inject(0) { |sum, w| sum += w.score }
    str = _("%{nick} played %{np} %{uno} games here, ") % {
      :nick => dnick, :np => np, :uno => UnoGame::UNO
    }
    str << _("forfeited %{nf} games, ") % { :nf => nf } if nf > 0
    str << _("won %{nw} games") % { :nw => nw}
    if nw > 0
      str << _(" with %{score} total points") % { :score => score }
      avg = ps.won.inject(0) { |sum, w| sum += w.score/w.opponents }/nw
      str << _(" and an average of %{avg} points per opponent") % { :avg => avg }
    end
    m.reply str
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
    @games[m.channel].drop_player(p[:nick] || m.source.nick)
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

  def do_top(m, p)
    pstats = chan_pstats(m.channel)
    scores = []
    wins = []
    pstats.each do |k, v|
      wins << [v.won.length, k]
      scores << [v.won.inject(0) { |s, w| s+=w.score }, k]
    end

    if n = p[:scorenum]
      msg = _("%{uno} %{num} highest scores: ") % {
        :uno => UnoGame::UNO, :num => p[:scorenum]
      }
      scores.sort! { |a1, a2| -(a1.first <=> a2.first) }
      scores = scores[0, n.to_i].compact
      i = 0
      if scores.length <= 5
        list = "\n" + scores.map { |a|
          i+=1
          _("%{i}. %{b}%{nick}%{b} with %{b}%{score}%{b} points") % {
            :i => i, :b => Bold, :nick => a.last, :score => a.first
          }
        }.join("\n")
      else
        list = scores.map { |a|
          i+=1
          _("%{i}. %{nick} ( %{score} )") % {
            :i => i, :nick => a.last, :score => a.first
          }
        }.join(" | ")
      end
    elsif n = p[:winnum]
      msg = _("%{uno} %{num} most wins: ") % {
        :uno => UnoGame::UNO, :num => p[:winnum]
      }
      wins.sort! { |a1, a2| -(a1.first <=> a2.first) }
      wins = wins[0, n.to_i].compact
      i = 0
      if wins.length <= 5
        list = "\n" + wins.map { |a|
          i+=1
          _("%{i}. %{b}%{nick}%{b} with %{b}%{score}%{b} wins") % {
            :i => i, :b => Bold, :nick => a.last, :score => a.first
          }
        }.join("\n")
      else
        list = wins.map { |a|
          i+=1
          _("%{i}. %{nick} ( %{score} )") % {
            :i => i, :nick => a.last, :score => a.first
          }
        }.join(" | ")
      end
    else
      msg = _("uh, what kind of score list did you want, again?")
      list = _(" I can only show the top scores (with top) and the most wins (with topwin)")
    end
    m.reply msg + list, :max_lines => (msg+list).count("\n")+1
  end
end

pg = UnoPlugin.new

pg.map 'uno', :private => false, :action => :create_game
pg.map 'uno end', :private => false, :action => :end_game, :auth_path => 'manage'
pg.map 'uno drop', :private => false, :action => :drop_player, :auth_path => 'manage::drop::self!'
pg.map 'uno giveup', :private => false, :action => :drop_player, :auth_path => 'manage::drop::self!'
pg.map 'uno drop :nick', :private => false, :action => :drop_player, :auth_path => 'manage::drop::other!'
pg.map 'uno replace :old [with] :new', :private => false, :action => :replace_player, :auth_path => 'manage'
pg.map 'uno transfer [game [ownership]] [to] :nick', :private => false, :action => :transfer_ownership, :auth_path => 'manage'
pg.map 'uno stock', :private => false, :action => :print_stock
pg.map 'uno chanstats', :private => false, :action => :do_chanstats
pg.map 'uno stats [:nick]', :private => false, :action => :do_pstats
pg.map 'uno top :scorenum', :private => false, :action => :do_top, :defaults => { :scorenum => 5 }
pg.map 'uno topwin :winnum', :private => false, :action => :do_top, :defaults => { :winnum => 5 }

pg.default_auth('stock', false)
pg.default_auth('manage', false)
pg.default_auth('manage::drop::self', true)
