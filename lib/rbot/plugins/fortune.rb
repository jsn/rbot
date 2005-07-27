class FortunePlugin < Plugin
  def help(plugin, topic="")
    "fortune [<module>] => get a (short) fortune, optionally specifying fortune db"
  end
  def fortune(m, params)
    db = params[:db]
    fortune = nil
    ["/usr/games/fortune", "/usr/bin/fortune", "/usr/local/bin/fortune"].each {|f|
      if FileTest.executable? f
        fortune = f
        break
      end
    }
    m.reply "fortune binary not found" unless fortune
    ret = Utils.safe_exec(fortune, "-n", "255", "-s", db)
    m.reply ret.gsub(/\t/, "  ").split(/\n/).join(" ")
    return
  end
end
plugin = FortunePlugin.new
plugin.map 'fortune :db', :defaults => {:db => 'fortunes'},
                          :requirements => {:db => /^[^-][\w-]+$/}
