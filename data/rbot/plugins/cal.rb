class CalPlugin < Plugin
  def help(plugin, topic="")
    "cal [month year] => show current calendar [optionally specify month and year]"
  end
  def cal(m, params)
    if params.has_key?(:month)
      m.reply Utils.safe_exec("cal", params[:month], params[:year])
    else
      m.reply Utils.safe_exec("cal")
    end
  end
end
plugin = CalPlugin.new
plugin.map 'cal :month :year', :requirements => {:month => /^\d+$/, :year => /^\d+$/}
plugin.map 'cal'
