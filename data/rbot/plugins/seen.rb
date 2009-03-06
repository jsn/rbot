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
    :desc => _("Maximum number of seen users to return in search (0 = no limit)."))

  def help(plugin, topic="")
    _("seen <nick> => have you seen, or when did you last see <nick>")
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

      m.reply _("nope!") if num_matched.zero?
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
      store m, Saw.new(m.sourcenick.dup, now, type,
                       m.target.to_s, m.message.dup)
    when QuitMessage
      return if m.address?
      store m, Saw.new(m.sourcenick.dup, now, "QUIT",
                       nil, m.message.dup)
    when NickMessage
      return if m.address?
      store m, Saw.new(m.oldnick, now, "NICK", nil, m.newnick)
    when PartMessage
      return if m.address?
      store m, Saw.new(m.sourcenick.dup, Time.new, "PART",
                       m.target.to_s, m.message.dup)
    when JoinMessage
      return if m.address?
      store m, Saw.new(m.sourcenick.dup, Time.new, "JOIN",
                       m.target.to_s, m.message.dup)
    when TopicMessage
      return if m.address? or m.info_or_set == :info
      store m, Saw.new(m.sourcenick.dup, Time.new, "TOPIC",
                       m.target.to_s, m.message.dup)
    end
  end

  def seen(reg)
    saw = case reg
    when Struct::Saw
      reg # for backwards compatibility
    when Array
      reg.last
    end

    before = reg.first

    formats = {
      :normal      => _("%{nick} was last seen %{when}, %{doing}"),
      :with_before => _("%{nick} was last seen %{when}, %{doing} and %{time} before %{did_before}")
    }

    if [:PART, :QUIT].include?(saw.type.to_sym) &&
       [:PUBLIC, :ACTION].include?(before.type.to_sym)
      did_before = case before.type.to_sym
      when :PUBLIC
        _("saying \"%{message}\"")
      when :ACTION
        _("doing *%{message}*")
      end % {
        :nick => saw.nick,
        :message => before.message
      }

      format = :with_before

      time_diff = saw.time - before.time
      if time_diff < 300
        time_before = _("a moment")
      elsif time_diff < 3600
        time_before = _("a while")
      else
        format = :normal
      end
    else
      format = :normal
    end

    nick = saw.nick
    ago = Time.new - saw.time

    if (ago.to_i == 0)
      time = _("just now")
    else
      time = _("%{time} ago") % { :time => Utils.secs_to_string(ago) }
    end

    doing = case saw.type.to_sym
    when :PUBLIC
      _("saying \"%{message}\"")
    when :ACTION
      _("doing %{nick} %{message}")
    when :NICK
      _("changing nick from %{nick} to %{message}")
    when :PART
      if saw.message.empty?
        _("leaving %{where}")
      else
        _("leaving %{where} (%{message})")
      end
    when :JOIN
      _("joining %{where}")
    when :QUIT
      _("quitting IRC (%{message})")
    when :TOPIC
      _("changing the topic of %{where} to \"%{message}\"")
    end % { :message => saw.message, :where => saw.where, :nick => saw.nick }

    case format
    when :normal
      formats[:normal] % {
        :nick  => saw.nick,
        :when  => time,
        :doing => doing,
      }
    when :with_before
      formats[:with_before] % {
        :nick  => saw.nick,
        :when  => time,
        :doing => doing,
        :time  => time_before,
        :did_before => did_before
      }
    end
  end

  def store(m, saw)
    reg = @registry[saw.nick]

    if reg && reg.is_a?(Array)
      reg.shift if reg.size > 1
      reg.push(saw)
    else
      reg = [saw]
    end

    if m.is_a? NickMessage
      @registry[m.newnick] = reg
    end

    @registry[saw.nick] = reg
  end
end
plugin = SeenPlugin.new
plugin.register("seen")
