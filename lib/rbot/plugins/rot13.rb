class RotPlugin < Plugin
  def help(plugin, topic="")
    "rot13 <string> => encode <string> to rot13 or back"
  end
  def privmsg(m)
    unless(m.params && m.params =~ /^.+$/)
      m.reply "incorrect usage: " + help(m.plugin)
      return
    end
    m.reply m.params.tr("A-Za-z", "N-ZA-Mn-za-m");
  end
end
plugin = RotPlugin.new
plugin.register("rot13")
