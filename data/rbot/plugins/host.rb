class HostPlugin < Plugin
  Config.register Config::StringValue.new('host.path',
     :default => '/usr/bin/host',
     :desc => _('Path to the host program'))

  def help(plugin, topic="")
    "host <domain> => query nameserver about domain names and zones for <domain>"
  end

  def host_path
    @bot.config["host.path"]
  end

  def privmsg(m)
    unless(m.params =~ /^(\w|-|\.)+$/)
      m.reply "incorrect usage: " + help(m.plugin)
      return
    end
    m.reply Utils.safe_exec(host_path, m.params)
  end
end
plugin = HostPlugin.new
plugin.register("host")
