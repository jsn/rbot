RouletteHistory = Struct.new("RouletteHistory", :games, :shots, :deaths, :misses, :wins)

class RoulettePlugin < Plugin
  def initialize
    super
    reload
  end
  def help(plugin, topic="")
    "roulette => play russian roulette - starts a new game if one isn't already running. One round in a six chambered gun. Take turns to say roulette to the bot, until somebody dies. roulette reload => force the gun to reload, roulette stats => show stats from all games, roulette stats <player> => show stats for <player>, roulette clearstats => clear stats (config level auth required)"
  end
  def privmsg(m)
    if m.params == "reload"
      @bot.action m.replyto, "reloads"
      reload
      # all players win on a reload
      # (allows you to play 3-shot matches etc)
      @players.each {|plyr|
        pdata = @registry[plyr]
        next if pdata == nil
        pdata.wins += 1
        @registry[plyr] = pdata
      }
      return
    elsif m.params == "stats"
      m.reply stats
      return
    elsif m.params =~ /^stats\s+(.+)$/
      m.reply(playerstats($1))
      return
    elsif m.params == "clearstats"
      if @bot.auth.allow?("config", m.source, m.replyto)
        @registry.clear
        @bot.okay m.replyto
      end
      return
    elsif m.params
      m.reply "incorrect usage: " + help(m.plugin)
      return
    end
    if m.private?
      m.reply "you gotta play roulette in channel dude"
      return
    end

    playerdata = nil
    if @registry.has_key?(m.sourcenick)
      playerdata = @registry[m.sourcenick]
    else
      playerdata = RouletteHistory.new(0,0,0,0,0)
    end
    
    unless @players.include?(m.sourcenick)
      @players << m.sourcenick
      playerdata.games += 1
    end
    playerdata.shots += 1
    
    shot = @chambers.pop
    if shot
      m.reply "#{m.sourcenick}: chamber #{6 - @chambers.length} of 6 => *BANG*"
      playerdata.deaths += 1
      @players.each {|plyr|
        next if plyr == m.sourcenick
        pdata = @registry[plyr]
        next if pdata == nil
        pdata.wins += 1
        @registry[plyr] = pdata
      }
    else
      m.reply "#{m.sourcenick}: chamber #{6 - @chambers.length} of 6 => +click+"
      playerdata.misses += 1
    end

    @registry[m.sourcenick] = playerdata
    
    if shot || @chambers.empty?
      @bot.action m.replyto, "reloads"
      reload
    end
  end
  def reload
    @chambers = [false, false, false, false, false, false]
    @chambers[rand(@chambers.length)] = true
    @players = Array.new
  end
  def playerstats(player)
    pstats = @registry[player]
    return "#{player} hasn't played enough games yet" if pstats.nil?
    return "#{player} has played #{pstats.games} games, won #{pstats.wins} and lost #{pstats.deaths}. #{player} pulled the trigger #{pstats.shots} times and found the chamber empty on #{pstats.misses} occasions."
  end
  def stats
    total_players = 0
    total_games = 0
    total_shots = 0
    
    died_most = [nil,0]
    won_most = [nil,0]
    h_win_percent = [nil,0]
    l_win_percent = [nil,0]
    h_luck_percent = [nil,0]
    l_luck_percent = [nil,0]
    @registry.each {|k,v|
      total_players += 1
      total_games += v.deaths
      total_shots += v.shots
      
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
    return "roulette stats: no games played yet" if total_games < 1
    return "roulette stats: #{total_games} games completed, #{total_shots} shots fired at #{total_players} players. Luckiest: #{h_luck_percent[0].join(',')} (#{sprintf '%.1f', h_luck_percent[1]}% clicks). Unluckiest: #{l_luck_percent[0].join(',')} (#{sprintf '%.1f', l_luck_percent[1]}% clicks). Highest survival rate: #{h_win_percent[0].join(',')} (#{sprintf '%.1f', h_win_percent[1]}%). Lowest survival rate: #{l_win_percent[0].join(',')} (#{sprintf '%.1f', l_win_percent[1]}%). Most wins: #{won_most[0].join(',')} (#{won_most[1]}). Most deaths: #{died_most[0].join(',')} (#{died_most[1]})."
  end
end
plugin = RoulettePlugin.new
plugin.register("roulette")
