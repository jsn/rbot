class RotPlugin < Plugin
  def help(plugin, topic="")
    "rot13 <string> => encode <string> to rot13 or back"
  end
  def rot13(m, params)
    m.reply params[:string].join(" ").tr("A-Za-z", "N-ZA-Mn-za-m");
  end
end
plugin = RotPlugin.new
plugin.map 'rot13 *string'
