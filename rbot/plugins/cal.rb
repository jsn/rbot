class CalPlugin < Plugin
  def help(plugin, topic="")
    "cal [options] => show current calendar [unix cal options]"
  end
  def privmsg(m)
    if m.params && m.params.length > 0
      m.reply Utils.safe_exec("cal", m.params) 
    else
      m.reply Utils.safe_exec("cal")
    end
  end
end
plugin = CalPlugin.new
plugin.register("cal")
