class FortunePlugin < Plugin
  def help(plugin, topic="")
    "fortune [<module>] => get a (short) fortune, optionally specifying fortune db"
  end
  def privmsg(m)
    case m.params
    when (/\B-/)
      m.reply "incorrect usage: " + help(m.plugin)
      return
    when (/^([\w-]+)$/)
      db = $1
    when nil
      db = "fortunes"
    else
      m.reply "incorrect usage: " + help(m.plugin)
      return
    end
    fortune = nil
    ["/usr/games/fortune", "/usr/bin/fortune", "/usr/local/bin/fortune"].each {|f|
      fortune = f if FileTest.executable? f
    }
    m.reply "fortune not found" unless fortune
    ret = Utils.safe_exec(fortune, "-n", "255", "-s", db)
    m.reply ret.gsub(/\t/, "  ").split(/\n/).join(" ")
    return
  end
end
plugin = FortunePlugin.new
plugin.register("fortune")
