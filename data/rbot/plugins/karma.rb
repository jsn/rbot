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
    oldkarma = @bot.path 'karma.rbot'
    if File.exist? oldkarma
      log "importing old karma data"
      IO.foreach(oldkarma) do |line|
        if(line =~ /^(\S+)<=>([\d-]+)$/)
          item = $1
          karma = $2.to_i
          @registry[item] = karma
        end
      end
      File.delete oldkarma
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

  def setkarma(m, params)
    thing = (params[:key] || m.sourcenick).to_s
    @registry[thing] = params[:val].to_i
    karma(m, params)
  end
  
  def help(plugin, topic="")
    "karma module: Listens to everyone's chat. <thing>++/<thing>-- => increase/decrease karma for <thing>, karma for <thing>? => show karma for <thing>, karmastats => show stats. Karma is a community rating system - only in-channel messages can affect karma and you cannot adjust your own."
  end

  def message(m)
    return unless m.public? && m.message.match(/\+\+|--/)
    arg = nil
    op = nil
    ac = Hash.new
    m.message.split.each_with_index do |tok, i|
      tok.sub!(/[:,]$/, '') if i == 0
      catch :me_if_you_can do
        if m.channel.users[tok].nil?
          if (tok =~ /^(?:--)(.*[^-].*)$/) || (tok =~ /^(.*[^-].*)(?:--)$/)
            op, arg = '--', $1
            next
          elsif (tok =~ /^(?:\+\+)(.*[^+].*)$/)||(tok =~ /^(.*[^+].*)(?:\+\+)$/)
            op, arg = '++', $1
            next
          end
        end

        if (tok =~ /^--+$/) || (tok =~ /^\+\++$/)
          op = tok.slice(0, 2)
        else
          arg = tok
        end
      end # catch

      if op && arg
        ac[arg] ||= 0
        ac[arg] += (op == '--' ? -1 : 1)
        op = arg = nil
      end
    end

    ac.each do |k, v|
      next if v == 0
      @registry[k] += (v > 0 ? 1 : -1)
      m.reply @bot.lang.get("thanks") if k == @bot.nick && v > 0
    end
  end
end

plugin = KarmaPlugin.new

plugin.default_auth( 'edit', false )

plugin.map 'karmastats', :action => 'stats'
plugin.map 'karma :key', :defaults => {:key => false}
plugin.map 'setkarma :key :val', :defaults => {:key => false}, :requirements => {:val => /^-?\d+$/}, :auth_path => 'edit::set!'
plugin.map 'karma for :key'
