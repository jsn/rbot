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
      prepend = ( rex =~ /^\w/ ? '(?:\b)' : '')
      append = ( rex =~ /\w$/ ? '(?:\b|$)' : '')
      @trigger << Regexp.new(/#{prepend}#{Regexp.escape(rex)}#{append}/ui)
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
    elsif rex.sub!(/^ruby:/,'')
      act = :ruby
    end
    @replies << Reply.new(self, act, rex, *args)
    make_ranges
    return @replies.last
  end

  def rm_reply(num)
    @replies.delete_at(num-1)
    make_ranges
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
      raise LoadError, "corrupted reaction database" unless @reactions
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
    when :move
      "reaction move <trigger> to <other> => move all reactions to <trigger> to the new trigger <other>"
    when :chance, :chances
      "reaction chances are expressed either in terms of percentage (like 30%) or in terms of floating point numbers (like 0.3), and are clipped to be " +
      "between 0 and 1 (i.e. 0% and 100%). A reaction can have multiple replies, each with a different chance; if the total of the chances is less than one, " +
      "there is a chance that the trigger will not actually cause a reply. Otherwise, the chances express the relative frequency of the replies."
    when :trigger, :triggers
      "reaction triggers can have one of the format: single_word 'multiple words' \"multiple words \" /regular_expression/ !regular_expression!. " +
      "If prefixed by 'act:' (e.g. act:/(order|command)s/) the bot will only respond if a CTCP ACTION matches the trigger"
    when :reply, :replies
      "reaction replies are simply messages that the bot will reply when a trigger is matched. " +
      "Replies prefixed by 'act:' (e.g. act:goes shopping) signify that the bot should act instead of saying the message. " +
      "Replies prefixed by 'cmd:' or 'command:' (e.g. cmd:lart %{who}) issue a command to the bot. " +
      "Replies can use the %{key} syntax to access the following keys: " +
      "who (user that said the trigger), bot (bot's own nick), " +
      "target (first word following the trigger), what (whatever follows target), " +
      "before (everything that precedes the trigger), after, (everything that follows the trigger), " +
      "match (matched text), match1, match2, ... (the i-th capture). " +
      "Replies prefixed by 'ruby:' (e.g. ruby:m.reply 'Hello ' + subs[:who]) are interpreted as ruby code. " +
      "No %{key} substitution is done in this case, use the subs hash in the code instead. " +
      "Be warned that creating ruby replies can open unexpected security holes in the bot."
    when :list
      "reaction list [n]: lists the n-the page of programmed reactions (30 reactions are listed per page)"
    when :show
      "reaction show <trigger>: list the programmed replies to trigger <trigger>"
    else
      "reaction topics: add, remove, delete, rm, del, move, triggers, replies, chance, list, show"
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
    act, arg = reply.apply(subs)
    case act
    when :ruby
      begin
        # no substitutions for ruby code
        eval(reply.reply)
      rescue Exception => e
        error e
      end
    when :cmd
      begin
        # Pass the new message back to the bot.
        # FIXME Maybe we should do it the alias way, only calling
        # @bot.plugins.privmsg() ?
        fake_message(@bot.nick+": "+arg, :from => m)
      rescue RecurseTooDeep => e
        error e
      end
    when :reply
      m.plainreply arg
    else
      m.__send__(act, arg)
    end
  end

  def find_reaction(trigger)
    @reactions.find { |react|
      react.raw_trigger.downcase == trigger.downcase
    }
  end

  def can_add?(m, reaction)
    return true if reaction.act == :reply
    return true if reaction.act == :ruby and @bot.auth.permit?(m.source, "reaction::react::ruby", m.channel)
    return true if reaction.act == :cmd and @bot.auth.permit?(m.source, "reaction::react::cmd", m.channel)
    return false
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

    new_reaction = false

    reaction = find_reaction(trigger)
    if not reaction
      reaction = Reaction.new(trigger)
      @reactions << reaction
      new_reaction = true
    end

    found = reaction.find_reply(reply)
    if found
      # ruby replies need special permission
      if can_add?(m, found)
        found.pct = pct
        found.author = m.sourcenick
        found.date = Time.now
        found.channel = m.channel
      else
        m.reply _("Sorry, you're not allowed to change %{act} replies here") % {
          :act => found.act
        }
        return
      end
    else
      found = reaction.add_reply(reply, pct, m.sourcenick, Time.now, m.channel)
      unless can_add?(m, found)
        m.reply _("Sorry, you're not allowed to add %{act} replies here") % {
          :act => found.act
        }
        reaction.rm_reply(reaction.replies.length)
        if new_reaction
          @reactions.delete(reaction)
        end
        return
      end
    end

    if new_reaction
      m.reply "Ok, I'll start reacting to #{reaction.raw_trigger}"
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
    n = params[:n]
    n = n.to_i if n
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

# ruby reactions are security holes, so give stricter permission
plugin.default_auth('react::ruby', false)
# cmd reactions can be security holes too
plugin.default_auth('react::cmd', false)

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
