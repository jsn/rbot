class FigletPlugin < Plugin
  def help(plugin, topic="")
    "figlet [<message>] => print using figlet"
  end
  def privmsg(m)
	  case m.params
	  when nil
		  m.reply "incorrect usage: " + help(m.plugin)
		  return
	  when (/^-/)
		  m.reply "incorrect usage: " + help(m.plugin)
		  return
	  else
		  m.reply Utils.safe_exec("/usr/bin/figlet", "-k", "-f", "mini", m.params)
		  return
	  end
  end
end
plugin = FigletPlugin.new
plugin.register("figlet")
