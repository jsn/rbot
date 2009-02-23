#-- vim:sw=2:et
#++
#
# :title: Seen Plugin
#
# Keep a database of who last said/did what

define_structure :Saw, :nick, :time, :type, :where, :message

class SeenPlugin < Plugin
  Config.register Config::IntegerValue.new('seen.max_results',
    :default => 3, :validate => Proc.new{|v| v >= 0},
    :desc => "Maximum number of seen users to return in search (0 = no limit).")

  def help(plugin, topic="")
    "seen <nick> => have you seen, or when did you last see <nick>"
  end

  def privmsg(m)
    unless(m.params =~ /^(\S)+$/)
      m.reply "incorrect usage: " + help(m.plugin)
      return
    end

    m.params.gsub!(/\?$/, "")

    if @registry.has_key?(m.params)
      m.reply seen(@registry[m.params])
    else
      rx = Regexp.new(m.params, true)
      num_matched = 0
      @registry.each {|nick, saw|
        if nick.match(rx)
          m.reply seen(saw)
          num_matched += 1
          break if num_matched == @bot.config['seen.max_results']
        end
      }

      m.reply "nope!" if num_matched.zero?
    end
  end

  def listen(m)
    return unless m.source
    # keep database up to date with who last said what
    now = Time.new
    case m
    when PrivMessage
      return if m.private?
      type = m.action? ? 'ACTION' : 'PUBLIC'
      @registry[m.sourcenick] = Saw.new(m.sourcenick.dup, now, type,
                                          m.target.to_s, m.message.dup)
    when QuitMessage
      return if m.address?
      @registry[m.sourcenick] = Saw.new(m.sourcenick.dup, now, "QUIT",
                                        nil, m.message.dup)
    when NickMessage
      return if m.address?
      saw = Saw.new(m.oldnick, now, "NICK", nil, m.newnick)
      @registry[m.oldnick] = saw
      @registry[m.newnick] = saw
    when PartMessage
      return if m.address?
      @registry[m.sourcenick] = Saw.new(m.sourcenick.dup, Time.new, "PART",
                                        m.target.to_s, m.message.dup)
    when JoinMessage
      return if m.address?
      @registry[m.sourcenick] = Saw.new(m.sourcenick.dup, Time.new, "JOIN",
                                        m.target.to_s, m.message.dup)
    when TopicMessage
      return if m.address? or m.info_or_set == :info
      @registry[m.sourcenick] = Saw.new(m.sourcenick.dup, Time.new, "TOPIC",
                                        m.target.to_s, m.message.dup)
    end
  end

  def seen(saw)
    ret = "#{saw.nick} was last seen "
    ago = Time.new - saw.time

    if (ago.to_i == 0)
      ret << "just now, "
    else
      ret << Utils.secs_to_string(ago) + " ago, "
    end

    case saw.type.to_sym
    when :PUBLIC
      ret << "saying #{saw.message}"
    when :ACTION
      ret << "doing #{saw.nick} #{saw.message}"
    when :NICK
      ret << "changing nick from #{saw.nick} to #{saw.message}"
    when :PART
      ret << "leaving #{saw.where}"
    when :JOIN
      ret << "joining #{saw.where}"
    when :QUIT
      ret << "quitting IRC (#{saw.message})"
    when :TOPIC
      ret << "changing the topic of #{saw.where} to #{saw.message}"
    end
  end

end
plugin = SeenPlugin.new
plugin.register("seen")
