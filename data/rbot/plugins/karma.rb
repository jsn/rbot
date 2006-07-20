class KarmaPlugin < Plugin
  def initialize
    super

    # this plugin only wants to store ints!
    class << @registry
      def store(val)
        val.to_i
      end
      def restore(val)
        val.to_i
      end
    end
    @registry.set_default(0)

    # import if old file format found
    if(File.exist?("#{@bot.botclass}/karma.rbot"))
      log "importing old karma data"
      IO.foreach("#{@bot.botclass}/karma.rbot") do |line|
        if(line =~ /^(\S+)<=>([\d-]+)$/)
          item = $1
          karma = $2.to_i
          @registry[item] = karma
        end
      end
      File.delete("#{@bot.botclass}/karma.rbot")
    end

  end

  def stats(m, params)
    if (@registry.length)
      max = @registry.values.max
      min = @registry.values.min
      best = @registry.to_hash.index(max)
      worst = @registry.to_hash.index(min)
      m.reply "#{@registry.length} items. Best: #{best} (#{max}); Worst: #{worst} (#{min})"
    end
  end

  def karma(m, params)
    thing = params[:key]
    thing = m.sourcenick unless thing
    thing = thing.to_s
    karma = @registry[thing]
    if(karma != 0)
      m.reply "karma for #{thing}: #{@registry[thing]}"
    else
      m.reply "#{thing} has neutral karma"
    end
  end
  
  
  def help(plugin, topic="")
    "karma module: Listens to everyone's chat. <thing>++/<thing>-- => increase/decrease karma for <thing>, karma for <thing>? => show karma for <thing>, karmastats => show stats. Karma is a community rating system - only in-channel messages can affect karma and you cannot adjust your own."
  end
  def listen(m)
    return unless m.kind_of?(PrivMessage) && m.public?
    # in channel message, the kind we are interested in
    if(m.message =~ /(\+\+|--)/)
      string = m.message.sub(/\W(--|\+\+)(\(.*?\)|[^(++)(\-\-)\s]+)/, "\2\1")
      seen = Hash.new
      while(string.sub!(/(\(.*?\)|[^(++)(\-\-)\s]+)(\+\+|--)/, ""))
        key = $1
        change = $2
        next if seen[key]
        seen[key] = true

        key.sub!(/^\((.*)\)$/, "\1")
        key.gsub!(/\s+/, " ")
        next unless(key.length > 0)
        next if(key == m.sourcenick)
        if(change == "++")
          @registry[key] += 1
        elsif(change == "--")
          @registry[key] -= 1
        end
      end
    end
  end
end
plugin = KarmaPlugin.new
plugin.map 'karmastats', :action => 'stats'
plugin.map 'karma :key', :defaults => {:key => false}
plugin.map 'karma for :key'
