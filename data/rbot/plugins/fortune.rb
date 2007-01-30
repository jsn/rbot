class FortunePlugin < Plugin
  BotConfig.register BotConfigStringValue.new('fortune.path',
    :default => '',
    :desc => "Full path to the fortune executable")

  def help(plugin, topic="")
    "fortune [<module>] => get a (short) fortune, optionally specifying fortune db"
  end
  def fortune(m, params)
    db = params[:db]
    fortune = @bot.config['fortune.path']
    if fortune.empty?
      ["/usr/share/games/fortune",
       "/usr/share/bin/fortune",
       "/usr/games/fortune",
       "/usr/bin/fortune",
       "/usr/local/games/fortune",
       "/usr/local/bin/fortune"].each {|f|
          if FileTest.executable? f
            fortune = f

            # Try setting the config entry
            config_par = {:key => 'fortune.path', :value => [f], :silent => true }
	    debug "Setting fortune.path to #{f}"
            set_path = @bot.plugins['config'].handle_set(m, config_par)
            if set_path
              debug "fortune.path set to #{@bot.config['fortune.path']}"
            else
              debug "couldn't set fortune.path"
            end

            break
          end
        }
    end
    m.reply "fortune binary not found" unless fortune
    begin
      ret = Utils.safe_exec(fortune, "-n", "255", "-s", db)
    rescue
      ret = "failed to execute fortune"
      # TODO reset fortune.path when execution fails
    end
    m.reply ret.gsub(/\t/, "  ").split(/\n/).join(" ")
    return
  end
end
plugin = FortunePlugin.new
plugin.map 'fortune :db', :defaults => {:db => 'fortunes'},
                          :requirements => {:db => /^[^-][\w-]+$/}
