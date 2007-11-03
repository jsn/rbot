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
  def initialize
    super

    # TODO config
    @dir = File.join(@bot.botclass,"factoids")
    @fname = File.join(@dir,"factoids.rbot")
    if File.exist?(@fname)
      @factoids = File.readlines(@fname)
      @factoids.each { |l| l.chomp! }
    else
      # A Set, maybe?
      @factoids = Array.new
    end
  end

  def save
    Dir.mkdir(@dir) unless FileTest.directory?(@dir)
    Utils.safe_save(@fname) do |file|
      file.puts @factoids
    end
  end

  def help(plugin, topic="")
    _("factoids plugin: learn that <factoid>, forget that <factoids>, facts about <words>")
  end

  def learn(m, params)
    factoid = params[:stuff].to_s
    if @factoids.index(factoid)
      m.reply _("I already know that %{factoid}" % { :factoid => factoid })
    else
      @factoids << factoid
      m.okay
    end
  end

  def forget(m, params)
    factoid = params[:stuff].to_s
    if @factoids.delete(factoid)
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

end

plugin = FactoidsPlugin.new
plugin.map 'learn that *stuff'
plugin.map 'forget that *stuff'
plugin.map 'facts [about *words]'
