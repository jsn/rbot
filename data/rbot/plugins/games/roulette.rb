define_structure :RouletteHistory, :games, :shots, :deaths, :misses, :wins, :points

class RoulettePlugin < Plugin
  Config.register Config::BooleanValue.new('roulette.autospin',
    :default => true,
    :desc => "Automatically spins the roulette at the butlast shot")
  Config.register Config::BooleanValue.new('roulette.kick',
    :default => false,
    :desc => "Kicks shot players from the channel")
  Config.register Config::BooleanValue.new('roulette.twice_in_a_row',
    :default => false,
    :desc => "Allow players to go twice in a row")

  def initialize
    super
    reset_chambers
    @players = Array.new
    @last = ''
  end

  def help(plugin, topic="")
    "roulette => play russian roulette - starts a new game if one isn't already running. One round in a six chambered gun. Take turns to say roulette to the bot, until somebody dies. roulette reload => force the gun to reload, roulette stats => show stats from all games, roulette stats <player> => show stats for <player>, roulette clearstats => clear stats (config level auth required), roulette spin => spins the cylinder"
  end

  def clearstats(m, params)
    @registry.clear
    m.okay
  end

  def roulette(m, params)
    if m.private?
      m.reply "you gotta play roulette in channel dude"
      return
    end

    playerdata = nil
    if @registry.has_key?("player " + m.sourcenick)
      playerdata = @registry["player " + m.sourcenick]
    else
      playerdata = RouletteHistory.new(0,0,0,0,0,0)
    end

    totals = nil
    if @registry.has_key?("totals")
      totals = @registry["totals"]
    else
      totals = RouletteHistory.new(0,0,0,0,0,0)
    end

    if @last == m.sourcenick and not @bot.config['roulette.twice_in_a_row']
      m.reply "you can't go twice in a row!"
      return
    end

    @last = m.sourcenick
    unless @players.include?(m.sourcenick)
      @players << m.sourcenick
      playerdata.games += 1
    end
    playerdata.shots += 1
    totals.shots += 1

    shot = @chambers.pop
    chamberNo = 6 - @chambers.length
    if shot
      m.reply "#{m.sourcenick}: chamber #{chamberNo} of 6 => *BANG*"
      playerdata.deaths += 1
      totals.deaths += 1
      @players.each {|plyr|
        next if plyr == m.sourcenick
        pdata = @registry["player " + plyr]
        next if pdata == nil
        pdata.wins += 1
        totals.wins += 1
        @registry["player " + plyr] = pdata
      }
      @players.clear
      @last = ''
      @bot.kick(m.replyto, m.sourcenick, "*BANG*") if @bot.config['roulette.kick']
    else
      m.reply "#{m.sourcenick}: chamber #{chamberNo} of 6 => +click+"
      playerdata.misses += 1
      playerdata.points += 2**chamberNo
      totals.misses += 1
    end

    @registry["player " + m.sourcenick] = playerdata
    @registry["totals"] = totals

    if shot || @chambers.empty?
      reload(m)
    elsif @chambers.length == 1 and @bot.config['roulette.autospin']
      spin(m)
    end
  end

  def reload(m, params = {})
    if m.private?
      m.reply "you gotta play roulette in channel dude"
      return
    end

    m.act "reloads"
    reset_chambers
    # all players win on a reload
    # (allows you to play 3-shot matches etc)
    totals = nil
    if @registry.has_key?("totals")
      totals = @registry["totals"]
    else
      totals = RouletteHistory.new(0,0,0,0,0,0)
    end

    @players.each {|plyr|
      pdata = @registry["player " + plyr]
      next if pdata == nil
      pdata.wins += 1
      totals.wins += 1
      @registry["player " + plyr] = pdata
    }

    totals.games += 1
    @registry["totals"] = totals

    @players.clear
    @last = ''
  end

  def spin(m, params={})
    # Spinning is just like resetting, except that nobody wins
    if m.private?
      m.reply "you gotta play roulette in channel dude"
      return
    end

    m.act "spins the cylinder"
    reset_chambers
  end

  def reset_chambers
    @chambers = [false, false, false, false, false, false]
    @chambers[rand(@chambers.length)] = true
  end

  def playerstats(m, params)
    player = params[:player]
    pstats = @registry["player " + player]
    if pstats.nil?
      m.reply "#{player} hasn't played enough games yet"
    else
      m.reply "#{player} has played #{pstats.games} games, won #{pstats.wins} and lost #{pstats.deaths}. #{player} pulled the trigger #{pstats.shots} times and found the chamber empty on #{pstats.misses} occasions."
    end
  end

  def stats(m, params)
    if @registry.has_key?("totals")
      totals = @registry["totals"]
      total_games = totals.games
      total_shots = totals.shots
    else
      total_games = 0
      total_shots = 0
    end

    total_players = 0

    died_most = [nil,0]
    won_most = [nil,0]
    h_win_percent = [nil,0]
    l_win_percent = [nil,0]
    h_luck_percent = [nil,0]
    l_luck_percent = [nil,0]
    @registry.each {|k,v|
      match = /player (.+)/.match(k)
      next unless match
      k = match[1]

      total_players += 1

      win_rate = v.wins.to_f / v.games * 100
      if h_win_percent[0].nil? || win_rate > h_win_percent[1] && v.games > 2
        h_win_percent = [[k], win_rate]
      elsif win_rate == h_win_percent[1] && v.games > 2
        h_win_percent[0] << k
      end
      if l_win_percent[0].nil? || win_rate < l_win_percent[1] && v.games > 2
        l_win_percent = [[k], win_rate]
      elsif win_rate == l_win_percent[1] && v.games > 2
        l_win_percent[0] << k
      end

      luck = v.misses.to_f / v.shots * 100
      if h_luck_percent[0].nil? || luck > h_luck_percent[1] && v.games > 2
        h_luck_percent = [[k], luck]
      elsif luck == h_luck_percent[1] && v.games > 2
        h_luck_percent[0] << k
      end
      if l_luck_percent[0].nil? || luck < l_luck_percent[1] && v.games > 2
        l_luck_percent = [[k], luck]
      elsif luck == l_luck_percent[1] && v.games > 2
        l_luck_percent[0] << k
      end

      if died_most[0].nil? || v.deaths > died_most[1]
        died_most = [[k], v.deaths]
      elsif v.deaths == died_most[1]
        died_most[0] << k
      end
      if won_most[0].nil? || v.wins > won_most[1]
        won_most = [[k], v.wins]
      elsif v.wins == won_most[1]
        won_most[0] << k
      end
    }
    if total_games < 1
      m.reply "roulette stats: no games completed yet"
    else
      m.reply "roulette stats: #{total_games} games completed, #{total_shots} shots fired at #{total_players} players. Luckiest: #{h_luck_percent[0].join(',')} (#{sprintf '%.1f', h_luck_percent[1]}% clicks). Unluckiest: #{l_luck_percent[0].join(',')} (#{sprintf '%.1f', l_luck_percent[1]}% clicks). Highest survival rate: #{h_win_percent[0].join(',')} (#{sprintf '%.1f', h_win_percent[1]}%). Lowest survival rate: #{l_win_percent[0].join(',')} (#{sprintf '%.1f', l_win_percent[1]}%). Most wins: #{won_most[0].join(',')} (#{won_most[1]}). Most deaths: #{died_most[0].join(',')} (#{died_most[1]})."
    end
  end

  # Figure out who the winnar is!
  def hof(m, params)
    fool = m.sourcenick
    tmpKey = params[:key].to_s
    targetKey = tmpKey.to_sym
    m.reply("Checking out the #{tmpKey} HoF...")
    tmp = @registry.to_hash
    tmp.delete("totals")
    sorted = tmp.sort { |a,b| b[1][targetKey] <=> a[1][targetKey] }

    winnersLeft = 5

    winners = []
    sorted.each do |player|
      playerName = player[0].split(" ")[1]
      if player[0] == "totals" or playerName == ""
        next
      end
      winners << "#{playerName} has #{player[1][targetKey]}"
      winnersLeft -= 1
      if winnersLeft == 0
        break
      end
    end
    m.reply(winners.join(" | "))
  end
end

plugin = RoulettePlugin.new

plugin.default_auth('clearstats', false)

plugin.map 'roulette reload', :action => 'reload'
plugin.map 'roulette spin', :action => 'spin'
plugin.map 'roulette stats :player', :action => 'playerstats'
plugin.map 'roulette stats', :action => 'stats'
plugin.map 'roulette clearstats', :action => 'clearstats'
plugin.map 'roulette hof :key', :action => 'hof', :defaults => {:key => "points"}, :requirements => {:key => /^(?:games|shots|deaths|misses|wins|points)$/}
plugin.map 'roulette'

