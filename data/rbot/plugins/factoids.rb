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
      "(this|that|a|the|an|all|both)\\s+(.*)\\s+(is|are)\\s+.*:2",
      "(this|that|a|the|an|all|both)\\s+(.*?)\\s+(is|are)\\s+.*:2",
      "(.*)\\s+(is|are)\\s+.*",
      "(.*?)\\s+(is|are)\\s+.*",
    ],
    :on_change => Proc.new { |bot, v| bot.plugins['factoids'].reset_triggers },
    :desc => "A list of regular expressions matching factoids where keywords can be identified. append ':n' if the keyword is defined by the n-th group instead of the first")
  Config.register Config::BooleanValue.new('factoids.address',
    :default => true,
    :desc => "Should the bot reply with relevant factoids only when addressed with a direct question? If not, the bot will attempt to lookup foo if someone says 'foo?' in channel")

  def initialize
    super

    # TODO config
    @dir = File.join(@bot.botclass,"factoids")
    @filename = "factoids.rbot"
    @factoids = FactoidList.new
    @triggers = Set.new
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

  def parse_for_trigger(f, rx=nil)
    if !rx
      regs = trigger_patterns_to_rx
    else
      regs = rx
    end
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

  def reset_triggers
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
    @triggers.replace(triggers)
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
      })
    else
      @factoids << factoid
      @changed = true
      m.okay
      fact(m, :index => @factoids.length.to_s)
      parse_for_trigger(factoid)
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

  def long_fact(fact,index=nil,total=@factoids.length)
    idx = index || @factoids.index(fact)+1
    _("fact #%{idx} of %{total}: %{fact}" % {
      :idx => idx,
      :total => total,
      :fact => fact.to_s(:meta => true)
    })
  end

  def facts(m, params)
    total = @factoids.length
    if params[:words].empty?
      m.reply _("I know %{total} facts" % { :total => total })
    else
      rx = Regexp.new(params[:words].to_s, true)
      known = @factoids.grep(rx)
      reply = []
      if known.empty?
        reply << _("I know nothing about %{words}" % params)
      else
        # TODO config
        max_facts = 5
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
          reply << long_fact(f)
        }
      end
      m.reply reply.join(" -- ")
    end
  end

  def unreplied(m)
    return if @bot.config['factoids.address'] and !m.address?
    return if @factoids.empty?
    return if @triggers.empty?
    return unless m.message =~ /^(.*)\?\s*$/
    query = $1.strip.downcase
    if @triggers.include?(query)
      facts(m, :words => query)
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
        rx = Regexp.new(params[:words].to_s, true)
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
plugin.map 'fact [about *words]'
plugin.map 'fact :index', :requirements => { :index => /^#?\d+$/ }

plugin.map 'fact :index :learn from *who', :action => :edit_fact, :requirements => { :learn => /^((?:is|was)\s+)?learn(ed|t)$/, :index => /^#?\d+$/ }, :auth_path => 'edit'
plugin.map 'fact :index :learn on *when',  :action => :edit_fact, :requirements => { :learn => /^((?:is|was)\s+)?learn(ed|t)$/, :index => /^#?\d+$/ }, :auth_path => 'edit'
plugin.map 'fact :index :learn in *where', :action => :edit_fact, :requirements => { :learn => /^((?:is|was)\s+)?learn(ed|t)$/, :index => /^#?\d+$/ }, :auth_path => 'edit'

plugin.map 'facts import [from] *filename', :action => :import, :auth_path => 'import'
