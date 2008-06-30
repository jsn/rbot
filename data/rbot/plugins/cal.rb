class CalPlugin < Plugin
  Config.register Config::StringValue.new('cal.path',
     :default => 'cal',
     :desc => _('Path to the cal program'))

  def help(plugin, topic="")
    "cal [month year] => show current calendar [optionally specify month and year]"
  end
  
  def cal_path
    @bot.config["cal.path"]
  end

  def cal(m, params)
    if params.has_key?(:month)
      m.reply Utils.safe_exec(cal_path, params[:month], params[:year])
    else
      m.reply Utils.safe_exec(cal_path)
    end
  end
end
plugin = CalPlugin.new
plugin.map 'cal :month :year', :requirements => {:month => /^\d+$/, :year => /^\d+$/}
plugin.map 'cal'
