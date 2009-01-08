#-- vim:sw=2:et
#++
#
# :title: ROT13 plugin
#
class RotPlugin < Plugin
  def initialize
    super
    @bot.register_filter(:rot13) { |s|
      ss = s.dup
      ss[:text] = s[:text].tr("A-Za-z", "N-ZA-Mn-za-m")
      ss
    }
  end

  def help(plugin, topic="")
    "rot13 <string> => encode <string> to rot13 or back"
  end

  def rot13(m, params)
    m.reply @bot.filter(:rot13, params[:string].to_s).to_s
  end
end
plugin = RotPlugin.new
plugin.map 'rot13 *string'
