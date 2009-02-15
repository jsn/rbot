#-- vim:sw=2:et
#++
#
# :title: Factoids pluing
#
# Author:: Giuseppe "Oblomov" Bilotta <giuseppe.bilotta@gmail.com>
# Copyright:: (C) 2007 Giuseppe Bilotta
# License:: GPLv2
#
# Store (and retrieve) unstructured one-sentence factoids

class FactoidsPlugin < Plugin

  class Factoid
    def initialize(hash)
      @hash = hash.reject { |k, val| val.nil? or val.empty? rescue false }
      raise ArgumentError, "no fact!" unless @hash[:fact]
      if String === @hash[:when]
        @hash[:when] = Time.parse @hash[:when]
      end
    end

    def to_s(opts={})
      show_meta = opts[:meta]
      fact = @hash[:fact]
      if !show_meta
        return fact
      end
      meta = ""
      metadata = []
      if @hash[:who]
        metadata << _("from %{who}" % @hash)
      end
      if @hash[:when]
        metadata << _("on %{when}" % @hash)
      end
      if @hash[:where]
        metadata << _("in %{where}" % @hash)
      end
      unless metadata.empty?
        meta << _(" [%{data}]" % {:data => metadata.join(" ")})
      end
      return fact+meta
    end

    def [](*args)
      @hash[*args]
    end

    def []=(*args)
      @hash.send(:[]=,*args)
    end

    def to_hsh
      return @hash
    end
    alias :to_hash :to_hsh
  end

  class FactoidList < ArrayOf
    def initialize(ar=[])
      super(Factoid, ar)
    end

    def index(f)
      fact = f.to_s
      return if fact.empty?
      self.map { |f| f[:fact] }.index(fact)
    end

    def delete(f)
      idx = index(f)
      return unless idx
      self.delete_at(idx)
    end

    def grep(x)
      self.find_all { |f|
        x === f[:fact]
      }
    end
  end

  # TODO default should be language-specific
  Config.register Config::ArrayValue.new('factoids.trigger_pattern',
    :default => [
      "(this|that|a|the|an|all|both)\\s+(.*)\\s+(is|are|has|have|does|do)\\s+.*:2",
      "(this|that|a|the|an|all|both)\\s+(.*?)\\s+(is|are|has|have|does|do)\\s+.*:2",
      "(.*)\\s+(is|are|has|have|does|do)\\s+.*",
      "(.*?)\\s+(is|are|has|have|does|do)\\s+.*",
    ],
    :on_change => Proc.new { |bot, v| bot.plugins['factoids'].reset_triggers },
    :desc => "A list of regular expressions matching factoids where keywords can be identified. append ':n' if the keyword is defined by the n-th group instead of the first. if the list is empty, any word will be considered a keyword")
  Config.register Config::ArrayValue.new('factoids.not_triggers',
    :default => [
      "this","that","the","a","right","who","what","why"
    ],
    :on_change => Proc.new { |bot, v| bot.plugins['factoids'].reset_triggers },
    :desc => "A list of words that won't be set as keywords")
  Config.register Config::BooleanValue.new('factoids.address',
    :default => true,
    :desc => "Should the bot reply with relevant factoids only when addressed with a direct question? If not, the bot will attempt to lookup foo if someone says 'foo?' in channel")
  Config.register Config::ArrayValue.new('factoids.learn_pattern',
    :default => [
      ".*\\s+(is|are|has|have)\\s+.*"
    ],
    :on_change => Proc.new { |bot, v| bot.plugins['factoids'].reset_learn_patterns },
    :desc => "A list of regular expressions matching factoids that the bot can learn. append ':n' if the factoid is defined by the n-th group instead of the whole match.")
  Config.register Config::BooleanValue.new('factoids.listen_and_learn',
    :default => false,
    :desc => "Should the bot learn factoids from what is being said in chat? if true, phrases matching patterns in factoids.learn_pattern will tell the bot when a phrase can be learned")
  Config.register Config::BooleanValue.new('factoids.silent_listen_and_learn',
    :default => true,
    :desc => "Should the bot be silent about the factoids he learns from the chat? If true, the bot will not declare what he learned every time he learns something from factoids.listen_and_learn being true")
  Config.register Config::IntegerValue.new('factoids.search_results',
    :default => 5,
    :desc => "How many factoids to display at a time")

  def initialize
    super

    # TODO config
    @dir = datafile
    @filename = "factoids.rbot"
    @factoids = FactoidList.new
    @triggers = Set.new
    @learn_patterns = []
    reset_learn_patterns
    begin
      read_factfile
    rescue
      debug $!
    end
    @changed = false
  end

  def read_factfile(name=@filename,dir=@dir)
    fname = File.join(dir,name)

    expf = File.expand_path(fname)
    expd = File.expand_path(dir)
    raise ArgumentError, _("%{name} (%{fname}) must be under %{dir}" % {
      :name => name,
      :fname => expf,
      :dir => dir
    }) unless expf.index(expd) == 0

    if File.exist?(fname)
      raise ArgumentError, _("%{name} is not a file" % {
        :name => name
      }) unless File.file?(fname)
      factoids = File.readlines(fname)
      return if factoids.empty?
      firstline = factoids.shift
      pattern = firstline.chomp.split(" | ")
      if pattern.length == 1 and pattern.first != "fact"
        factoids.unshift(firstline)
        factoids.each { |f|
          @factoids << Factoid.new( :fact => f.chomp )
        }
      else
        pattern.map! { |p| p.intern }
        raise ArgumentError, _("fact must be the last field") unless pattern.last == :fact
        factoids.each { |f|
          ar = f.chomp.split(" | ", pattern.length)
          @factoids << Factoid.new(Hash[*([pattern, ar].transpose.flatten)])
        }
      end
    else
      raise ArgumentError, _("%{name} (%{fname}) doesn't exist" % {
        :name => name,
        :fname => fname
      })
    end
    reset_triggers
  end

  def save
    return unless @changed
    Dir.mkdir(@dir) unless FileTest.directory?(@dir)
    fname = File.join(@dir,@filename)
    ar = ["when | who | where | fact"]
    @factoids.each { |f|
      ar << "%s | %s | %s | %s" % [ f[:when], f[:who], f[:where], f[:fact]]
    }
    Utils.safe_save(fname) do |file|
      file.puts ar
    end
    @changed = false
  end

  def trigger_patterns_to_rx
    return [] if @bot.config['factoids.trigger_pattern'].empty?
    @bot.config['factoids.trigger_pattern'].inject([]) { |list, str|
      s = str.dup
      if s =~ /:(\d+)$/
        idx = $1.to_i
        s.sub!(/:\d+$/,'')
      else
        idx = 1
      end
      list << [/^#{s}$/iu, idx]
    }
  end

  def learn_patterns_to_rx
    return [] if @bot.config['factoids.learn_pattern'].empty?
    @bot.config['factoids.learn_pattern'].inject([]) { |list, str|
      s = str.dup
      if s =~ /:(\d+)$/
        idx = $1.to_i
        s.sub!(/:\d+$/,'')
      else
        idx = 0
      end
      list << [/^#{s}$/iu, idx]
    }
  end

  def parse_for_trigger(f, rx=nil)
    if !rx
      regs = trigger_patterns_to_rx
    else
      regs = rx
    end
    if regs.empty?
      f.to_s.scan(/\w+/u)
    else
      regs.inject([]) { |list, a|
        r = a.first
        i = a.last
        m = r.match(f.to_s)
        if m
          list << m[i].downcase
        else
          list
        end
      }
    end
  end

  def reset_triggers
    return unless @factoids
    start_time = Time.now
    rx = trigger_patterns_to_rx
    triggers = @factoids.inject(Set.new) { |set, f|
      found = parse_for_trigger(f, rx)
      if found.empty?
        set
      else
        set | found
      end
    }
    debug "Triggers done in #{Time.now - start_time}"
    @triggers.replace(triggers - @bot.config['factoids.not_triggers'])
  end

  def reset_learn_patterns
    @learn_patterns.replace(learn_patterns_to_rx)
  end

  def help(plugin, topic="")
    _("factoids plugin: learn that <factoid>, forget that <factoids>, facts about <words>")
  end

  def learn(m, params)
    factoid = Factoid.new(
      :fact => params[:stuff].to_s,
      :when => Time.now,
      :who => m.source.fullform,
      :where => m.channel.to_s
    )
    if idx = @factoids.index(factoid)
      m.reply _("I already know that %{factoid} [#%{idx}]" % {
        :factoid => factoid,
        :idx => idx
      }) unless params[:silent]
    else
      @factoids << factoid
      @changed = true
      m.reply _("okay, learned fact #%{num}: %{fact}" % { :num => @factoids.length, :fact => @factoids.last}) unless params[:silent]
      trigs = parse_for_trigger(factoid)
      @triggers |= trigs unless trigs.empty?
    end
  end

  def forget(m, params)
    if params[:index]
      idx = params[:index].scan(/\d+/).first.to_i
      total = @factoids.length
      if idx <= 0 or idx > total
        m.reply _("please select a fact number between 1 and %{total}" % { :total => total })
        return
      end
      if factoid = @factoids.delete_at(idx-1)
        m.reply _("I forgot that %{factoid}" % { :factoid => factoid })
        @changed = true
      else
        m.reply _("I couldn't delete factoid %{idx}" % { :idx => idx })
      end
    else
      factoid = params[:stuff].to_s
      if @factoids.delete(factoid)
        @changed = true
        m.okay
      else
        m.reply _("I didn't know that %{factoid}" % { :factoid => factoid })
      end
    end
  end

  def short_fact(fact,index=nil,total=@factoids.length)
    idx = index || @factoids.index(fact)+1
    _("[%{idx}/%{total}] %{fact}" % {
      :idx => idx,
      :total => total,
      :fact => fact.to_s(:meta => false)
    })
  end

  def long_fact(fact,index=nil,total=@factoids.length)
    idx = index || @factoids.index(fact)+1
    _("fact #%{idx} of %{total}: %{fact}" % {
      :idx => idx,
      :total => total,
      :fact => fact.to_s(:meta => true)
    })
  end

  def words2rx(words)
    # When looking for words we separate them with
    # arbitrary whitespace, not whatever they came with
    pre = words.map { |w| Regexp.escape(w)}.join("\\s+")
    pre << '\b' if pre.match(/\b$/)
    pre = '\b' + pre if pre.match(/^\b/)
    return Regexp.new(pre, true)
  end

  def facts(m, params)
    total = @factoids.length
    if params[:words].nil_or_empty? and params[:rx].nil_or_empty?
      m.reply _("I know %{total} facts" % { :total => total })
    else
      if params[:words].empty?
        rx = Regexp.new(params[:rx].to_s, true)
      else
        rx = words2rx(params[:words])
      end
      known = @factoids.grep(rx)
      reply = []
      if known.empty?
        reply << _("I know nothing about %{words}" % params)
      else
        max_facts = @bot.config['factoids.search_results']
        len = known.length
        if len > max_facts
          m.reply _("%{len} out of %{total} facts refer to %{words}, I'll only show %{max}" % {
            :len => len,
            :total => total,
            :words => params[:words].to_s,
            :max => max_facts
          })
          while known.length > max_facts
            known.delete_one
          end
        end
        known.each { |f|
          reply << short_fact(f)
        }
      end
      m.reply reply.join(". "), :split_at => /\[\d+\/\d+\] /, :purge_split => false
    end
  end

  def unreplied(m)
    if m.message =~ /^(.*)\?\s*$/
      return if @bot.config['factoids.address'] and !m.address?
      return if @factoids.empty?
      return if @triggers.empty?
      query = $1.strip.downcase
      if @triggers.include?(query)
        facts(m, :words => query.split)
      end
    else
      return if m.address? # we don't learn stuff directed at us which is not an explicit learn command
      return if !@bot.config['factoids.listen_and_learn'] or @learn_patterns.empty?
      @learn_patterns.each do |pat, i|
        g = pat.match(m.message)
        if g and g[i]
          learn(m, :stuff => g[i], :silent => @bot.config['factoids.silent_listen_and_learn'])
          break
        end
      end
    end
  end

  def fact(m, params)
    fact = nil
    idx = 0
    total = @factoids.length
    if params[:index]
      idx = params[:index].scan(/\d+/).first.to_i
      if idx <= 0 or idx > total
        m.reply _("please select a fact number between 1 and %{total}" % { :total => total })
        return
      end
      fact = @factoids[idx-1]
    else
      known = nil
      if params[:words].empty?
        if @factoids.empty?
          m.reply _("I know nothing")
          return
        end
        known = @factoids
      else
        rx = words2rx(params[:words])
        known = @factoids.grep(rx)
        if known.empty?
          m.reply _("I know nothing about %{words}" % params)
          return
        end
      end
      fact = known.pick_one
      idx = @factoids.index(fact)+1
    end
    m.reply long_fact(fact, idx, total)
  end

  def edit_fact(m, params)
    fact = nil
    idx = 0
    total = @factoids.length
    idx = params[:index].scan(/\d+/).first.to_i
    if idx <= 0 or idx > total
      m.reply _("please select a fact number between 1 and %{total}" % { :total => total })
      return
    end
    fact = @factoids[idx-1]
    begin
      if params[:who]
        who = params[:who].to_s.sub(/^me$/, m.source.fullform)
        fact[:who] = who
        @changed = true
      end
      if params[:when]
        dstr = params[:when].to_s
        begin
          fact[:when] = Time.parse(dstr, "")
          @changed = true
        rescue
          raise ArgumentError, _("not a date '%{dstr}'" % { :dstr => dstr })
        end
      end
      if params[:where]
        fact[:where] = params[:where].to_s
        @changed = true
      end
    rescue Exception
      m.reply _("couldn't change learn data for fact %{fact}: %{err}" % {
        :fact => fact,
        :err => $!
      })
      return
    end
    m.okay
  end

  def import(m, params)
    fname = params[:filename].to_s
    oldlen = @factoids.length
    begin
      read_factfile(fname)
    rescue
      m.reply _("failed to import facts from %{fname}: %{err}" % {
        :fname => fname,
        :err => $!
      })
    end
    m.reply _("%{len} facts loaded from %{fname}" % {
      :fname => fname,
      :len => @factoids.length - oldlen
    })
    @changed = true
  end

end

plugin = FactoidsPlugin.new

plugin.default_auth('edit', false)
plugin.default_auth('import', false)

plugin.map 'learn that *stuff'
plugin.map 'forget that *stuff', :auth_path => 'edit'
plugin.map 'forget fact :index', :requirements => { :index => /^#?\d+$/ }, :auth_path => 'edit'
plugin.map 'facts [about *words]'
plugin.map 'facts search *rx'
plugin.map 'fact [about *words]'
plugin.map 'fact :index', :requirements => { :index => /^#?\d+$/ }

plugin.map 'fact :index :learn from *who', :action => :edit_fact, :requirements => { :learn => /^((?:is|was)\s+)?learn(ed|t)$/, :index => /^#?\d+$/ }, :auth_path => 'edit'
plugin.map 'fact :index :learn on *when',  :action => :edit_fact, :requirements => { :learn => /^((?:is|was)\s+)?learn(ed|t)$/, :index => /^#?\d+$/ }, :auth_path => 'edit'
plugin.map 'fact :index :learn in *where', :action => :edit_fact, :requirements => { :learn => /^((?:is|was)\s+)?learn(ed|t)$/, :index => /^#?\d+$/ }, :auth_path => 'edit'

plugin.map 'facts import [from] *filename', :action => :import, :auth_path => 'import'
