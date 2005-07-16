class HostPlugin < Plugin
  def help(plugin, topic="")
    "host <domain> => query nameserver about domain names and zones for <domain>"
  end
  def privmsg(m)
    unless(m.params =~ /^(\w|-|\.)+$/)
      m.reply "incorrect usage: " + help(m.plugin)
      return
    end
    m.reply Utils.safe_exec("host", m.params)
  end
end
plugin = HostPlugin.new
plugin.register("host")
