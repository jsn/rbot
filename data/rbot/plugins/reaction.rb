#-- vim:sw=2:et
#++
#
# :title: Reaction plugin
#
# Author:: Giuseppe Bilotta <giuseppe.bilotta@gmail.com>
# Copyright:: (C) 2007 Giuseppe Bilotta
# License:: GPLv2
#
# Build one-liner replies/reactions to expressions/actions in channel
#
# Very alpha stage, so beware of sudden reaction syntax changes

class ::Reaction
  attr_reader :trigger, :replies
  attr_reader :raw_trigger, :raw_replies

  class ::Reply
    attr_reader :act, :reply, :pct
    attr_accessor :range
    attr_reader :author, :date, :channel
    attr_writer :date

    def pct=(val)
      @pct = val
      @reaction.make_ranges
    end

    def author=(name)
      @author = name.to_s
    end

    def channel=(name)
      @channel = name.to_s
    end

    def initialize(reaction, act, expr, pct, author, date, channel)
      @reaction = reaction
      @act = act
      @reply = expr
      self.pct = pct
      self.author = author
      @date = date
      self.channel = channel
    end

    def to_s
      [
        "#{act} #{reply} (#{pct} chance)",
        @range ? "(#{@range})" : "",
        "(#{author}, #{channel}, #{date})"
      ].join(" ")
    end

    def apply(subs={})
      [act, reply % subs]
    end
  end

  def trigger=(expr)
    @raw_trigger = expr.dup
    act = false
    rex = expr.dup
    if rex.sub!(/^act:/,'')
      act = true
    end
    @trigger = [act]
    if rex.sub!(%r@^([/!])(.*)\1$@, '\2')
      @trigger << Regexp.new(rex, true)
    else
      rex.sub!(/^(["'])(.*)\1$/, '\2')
      @trigger << Regexp.new(/\b#{Regexp.escape(rex)}\b/ui)
    end
  end

  def add_reply(expr, *args)
    @raw_replies << expr.dup
    act = :reply
    rex = expr.dup
    if rex.sub!(/^act:/,'')
      act = :act
    elsif rex.sub!(/^(?:cmd|command):/,'')
      act = :cmd
    end
    @replies << Reply.new(self, act, rex, *args)
    make_ranges
    return @replies.last
  end

  def rm_reply(num)
    @replies.delete_at(num-1)
    return @raw_replies.delete_at(num-1)
  end

  def find_reply(expr)
    @replies[@raw_replies.index(expr)] rescue nil
  end

  def make_ranges
    totals = 0
    pcts = @replies.map { |rep|
      totals += rep.pct
      rep.pct
    }
    pcts.map! { |p|
      p/totals
    } if totals > 1
    debug "percentages: #{pcts.inspect}"

    last = 0
    @replies.each_with_index { |r, i|
      p = pcts[i]
      r.range = last..(last+p)
      last+=p
    }
    debug "ranges: #{@replies.map { |r| r.range}.inspect}"
  end

  def pick_reply
    pick = rand()
    debug "#{pick} in #{@replies.map { |r| r.range}.inspect}"
    @replies.each { |r|
      return r if r.range and r.range === pick
    }
    return nil
  end

  def ===(message)
    return nil if @trigger.first and not message.action
    return message.message.match(@trigger.last)
  end

  def initialize(trig)
    self.trigger=trig
    @raw_replies = []
    @replies = []
  end

  def to_s
    raw_trigger
  end

end

class ReactionPlugin < Plugin

  ADD_SYNTAX = 'react to *trigger with *reply [at :chance chance]'
  MOVE_SYNTAX = 'reaction move *source to *dest'
  # We'd like to use backreferences for the trigger syntax
  # but we can't because it will be merged with the Plugin#map()
  # regexp
  TRIGGER_SYNTAX = /^(?:act:)?(?:!.*?!|\/.*?\/|".*?"|'.*?'|\S+)/

  def add_syntax
    return ADD_SYNTAX
  end

  def move_syntax
    return MOVE_SYNTAX
  end

  def trigger_syntax
    return TRIGGER_SYNTAX
  end

  attr :reactions

  def initialize
    super
    if @registry.has_key?(:reactions)
      @reactions = @registry[:reactions]
      raise unless @reactions
    else
      @reactions = []
    end

    @subs = {
      :bold => Bold,
      :underline => Underline,
      :reverse => Reverse,
      :italic => Italic,
      :normal => NormalText,
      :color => Color,
      :colour => Color,
      :bot => @bot.myself,
    }.merge ColorCode
  end

  def save
    @registry[:reactions] = @reactions
  end

  def help(plugin, topic="")
    if plugin.to_sym == :react
      return "react to <trigger> with <reply> [at <chance> chance] => " +
      "create a new reaction to expression <trigger> to which the bot will reply <reply>, optionally at chance <chance>, " +
      "seek help for reaction trigger, reaction reply and reaction chance for more details"
    end
    case (topic.to_sym rescue nil)
    when :add
      help(:react)
    when :remove, :delete, :rm, :del
      "reaction #{topic} <trigger> [<n>] => removes reactions to expression <trigger>. If <n> (a positive integer) is specified, only remove the n-th reaction, otherwise remove the trigger completely"
    when :chance, :chances
      "reaction chances are expressed either in terms of percentage (like 30%) or in terms of floating point numbers (like 0.3), and are clipped to be " +
      "between 0 and 1 (i.e. 0% and 100%). A reaction can have multiple replies, each with a different chance; if the total of the chances is less than one, " +
      "there is a chance that the trigger will not actually cause a reply. Otherwise, the chances express the relative frequency of the replies."
    when :trigger, :triggers
      "reaction triggers can have one of the format: single_word 'multiple words' \"multiple words \" /regular_expression/ !regular_expression!. " + 
      "If prefixed by 'act:' (e.g. act:/(order|command)s/) the bot will only respond if a CTCP ACTION matches the trigger"
    when :reply, :replies
      "reaction replies are simply messages that the bot will reply when a trigger is matched. " +
      "Replies can be prefixed by 'act:' (e.g. act:goes shopping) to signify that the bot should act instead of saying the message. " +
      "Replies can be prefixed by 'cmd:' or 'command:' (e.g. cmd:lart %{who}) to issue a command to the bot. " +
      "Replies can use the %{key} syntax to access one of the following keys: " +
      "who (the user that said the trigger), bot (the bot's own nick), " +
      "target (the first word following the trigger), what (whatever follows target), " +
      "before (everything that precedes the trigger), after, (everything that follows the trigger), " +
      "match (the actual matched text), match1, match2, ... (the i-th capture)"
    when :list
      "reaction list [n]: lists the n-the page of programmed reactions (30 reactions are listed per page)"
    when :show
      "reaction show <trigger>: list the programmed replies to trigger <trigger>"
    else
      "reaction topics: add, remove, delete, rm, del, triggers, replies, chance, list, show"
    end
  end

  def unreplied(m)
    return unless PrivMessage === m
    debug "testing #{m} for reactions"
    return if @reactions.empty?
    candidates = @reactions.map { |react|
      blob = react === m
      blob ? [blob, react] : nil
    }.compact
    return if candidates.empty?
    match, wanted = candidates.sort { |m1, m2|
      # Order by longest matching text first,
      # and by number of captures second
      longer = m1.first[0].length <=> m2.first[0].length
      longer == 0 ? m1.first.length <=> m2.first.length : longer
    }.last
    matched = match[0]
    before = match.pre_match.strip
    after = match.post_match.strip
    target, what = after.split(/\s+/, 2)
    extra = {
      :who => m.sourcenick,
      :match => matched,
      :target => target,
      :what => what,
      :before => before,
      :after => after
    }
    match.to_a.each_with_index { |d, i|
      extra[:"match#{i}"] = d
    }
    subs = @subs.dup.merge extra
    reply = wanted.pick_reply
    debug "picked #{reply}"
    return unless reply
    args = reply.apply(subs)
    if args[0] == :cmd
      new_m = PrivMessage.new(@bot, m.server, m.source, m.target, @bot.nick+": "+args[1])
      @bot.plugins.delegate "listen", new_m
      @bot.plugins.privmsg(new_m) if new_m.address?
    else
      m.__send__(*args)
    end
  end

  def find_reaction(trigger)
    @reactions.find { |react|
      react.raw_trigger.downcase == trigger.downcase
    }
  end

  def handle_add(m, params)
    trigger = params[:trigger].to_s
    reply = params[:reply].to_s

    pct = params[:chance] || "1"
    if pct.sub!(/%$/,'')
      pct = (pct.to_f/100).clip(0,1)
    else
      pct = pct.to_f.clip(0,1)
    end

    reaction = find_reaction(trigger)
    if not reaction
      reaction = Reaction.new(trigger)
      @reactions << reaction
      m.reply "Ok, I'll start reacting to #{reaction.raw_trigger}"
    end
    found = reaction.find_reply(reply)
    if found
      found.pct = pct
      found.author = m.sourcenick
      found.date = Time.now
      found.channel = m.channel
    else
      found = reaction.add_reply(reply, pct, m.sourcenick, Time.now, m.channel)
    end
    m.reply "I'll react to #{reaction.raw_trigger} with #{reaction.raw_replies.last} (#{(reaction.replies.last.pct * 100).to_i}%)"
  end

  def handle_move(m, params)
    source = params[:source].to_s
    dest = params[:dest].to_s
    found = find_reaction(source)
    if not found
      m.reply "I don't react to #{source}"
      return
    end
    if find_reaction(dest)
      m.reply "I already react to #{dest}, so I won't move #{source} to #{dest}"
      return
    end
    found.trigger=dest
    m.reply "Ok, I'll react to #{found.raw_trigger} now"
  end

  def handle_rm(m, params)
    trigger = params[:trigger].to_s
    n = params[:n].to_i rescue nil
    debug trigger.inspect
    found = find_reaction(trigger)
    purged = nil
    if found
      if n
        if n < 1 or n > found.replies.length
          m.reply "Please specify an index between 1 and #{found.replies.length}"
          return
        end
        purged = found.rm_reply(n)
        if found.replies.length == 0
          @reactions.delete(found)
          purged = nil
        else
          purged = " with #{purged}"
        end
      else
        @reactions.delete(found)
      end
      m.reply "I won't react to #{found.raw_trigger}#{purged} anymore"
    else
      m.reply "no reaction programmed for #{trigger}"
    end
  end

  def handle_list(m, params)
    if @reactions.empty?
      m.reply "no reactions programmed"
      return
    end

    per_page = 30
    pages = @reactions.length / per_page + 1
    page = params[:page].to_i.clip(1, pages)

    str = @reactions[(page-1)*per_page, per_page].join(", ")

    m.reply "Programmed reactions (page #{page}/#{pages}): #{str}"
  end

  def handle_show(m, params)
    if @reactions.empty?
      m.reply "no reactions programmed"
      return
    end

    trigger = params[:trigger].to_s

    found = find_reaction(trigger)

    unless found
      m.reply "I'm not reacting to #{trigger}"
      return
    end

    m.reply found.replies.join(", ")
  end

end

plugin = ReactionPlugin.new

plugin.map plugin.add_syntax, :action => 'handle_add',
  :requirements => { :trigger => plugin.trigger_syntax }

plugin.map 'reaction list [:page]', :action => 'handle_list',
  :requirements => { :page => /^\d+$/ }

plugin.map 'reaction show *trigger', :action => 'handle_show'

plugin.map plugin.move_syntax, :action => 'handle_move',
  :requirements => {
    :source => plugin.trigger_syntax,
    :dest => plugin.trigger_syntax
  }

plugin.map 'reaction del[ete] *trigger [:n]', :action => 'handle_rm', :auth_path => 'del!',
  :requirements => { :trigger => plugin.trigger_syntax, :n => /^\d+$/ }
plugin.map 'reaction remove *trigger [:n]', :action => 'handle_rm', :auth_path => 'del!',
  :requirements => { :trigger => plugin.trigger_syntax, :n => /^\d+$/ }
plugin.map 'reaction rm *trigger [:n]', :action => 'handle_rm', :auth_path => 'del!',
  :requirements => { :trigger => plugin.trigger_syntax, :n => /^\d+$/ }
