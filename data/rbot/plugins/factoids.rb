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

    def to_s
      @hash[:fact]
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

  def initialize
    super

    # TODO config
    @dir = File.join(@bot.botclass,"factoids")
    @filename = "factoids.rbot"
    @factoids = FactoidList.new
    read_factfile
    @changed = false
  end

  def read_factfile(name=@filename,dir=@dir)
    fname = File.join(dir,name)
    if File.exist?(fname)
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
        raise ArgumentError, "fact must be the last field" unless pattern.last == :fact
        factoids.each { |f|
          ar = f.chomp.split(" | ", pattern.length)
          @factoids << Factoid.new(Hash[*([pattern, ar].transpose.flatten)])
        }
      end
    end
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
    if @factoids.index(factoid)
      m.reply _("I already know that %{factoid}" % { :factoid => factoid })
    else
      @factoids << factoid
      @changed = true
      m.okay
    end
  end

  def forget(m, params)
    factoid = params[:stuff].to_s
    if @factoids.delete(factoid)
      @changed = true
      m.okay
    else
      m.reply _("I didn't know that %{factoid}" % { :factoid => factoid })
    end
  end

  def facts(m, params)
    if params[:words].empty?
      m.reply _("I know %{count} facts" % { :count => @factoids.length })
    else
      rx = Regexp.new(params[:words].to_s, true)
      known = @factoids.grep(rx)
      if known.empty?
        m.reply _("I know nothing about %{words}" % params)
      else
        m.reply known.join(" | "), :split_at => /\s+\|\s+/
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
    meta = nil
    metadata = []
    if fact[:who]
      metadata << _("from %{who}" % fact.to_hash)
    end
    if fact[:when]
      metadata << _("on %{when}" % fact.to_hash)
    end
    if fact[:where]
      metadata << _("in %{where}" % fact.to_hash)
    end
    unless metadata.empty?
      meta = _(" [learnt %{data}]" % {:data => metadata.join(" ")})
    end
    m.reply _("fact #%{idx} of %{total}: %{fact}%{meta}" % {
      :idx => idx,
      :total => total,
      :fact => fact,
      :meta => meta
    })
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
        debug who
        fact[:who] = who
      end
      if params[:when]
        fact[:when] = Time.parse(params[:when].to_s)
      end
      if params[:where]
        fact[:where] = params[:where].to_s
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

end

plugin = FactoidsPlugin.new

plugin.default_auth('edit', false)

plugin.map 'learn that *stuff'
plugin.map 'forget that *stuff', :auth_path => 'edit'
plugin.map 'facts [about *words]'
plugin.map 'fact [about *words]'
plugin.map 'fact :index', :requirements => { :index => /^#?\d+$/ }
plugin.map 'fact :index :learn from *who', :action => :edit_fact, :requirements => { :learn => /^((?:is|was)\s+)?learn(ed|t)$/, :index => /^#?\d+$/ }, :auth_path => 'edit'
plugin.map 'fact :index :learn on *when',  :action => :edit_fact, :requirements => { :learn => /^((?:is|was)\s+)?learn(ed|t)$/, :index => /^#?\d+$/ }, :auth_path => 'edit'
plugin.map 'fact :index :learn in *where', :action => :edit_fact, :requirements => { :learn => /^((?:is|was)\s+)?learn(ed|t)$/, :index => /^#?\d+$/ }, :auth_path => 'edit'
