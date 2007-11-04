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

    def to_hsh
      return @hash
    end
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
    m.reply _("fact %{idx}/%{total}: %{fact}" % {
      :idx => idx,
      :total => @factoids.length,
      :fact => fact
    })
  end

end

plugin = FactoidsPlugin.new
plugin.map 'learn that *stuff'
plugin.map 'forget that *stuff'
plugin.map 'facts [about *words]'
plugin.map 'fact [about *words]'
