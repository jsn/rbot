#DEFAULT_FONT="smslant"
DEFAULT_FONT="rectangles"
MAX_WIDTH=68

class FigletPlugin < Plugin
  def help(plugin, topic="")
    "figlet <message> => print using figlet"
  end

  def figlet(m, params)
    message = params[:message].to_s
    if message =~ /^-/
      m.reply "the message can't start with a - sign"
      return
    end
    m.reply Utils.safe_exec("/usr/bin/figlet", "-k", "-w", "#{MAX_WIDTH}", "-f", DEFAULT_FONT, message)
    return
  end
end

plugin = FigletPlugin.new
plugin.map "figlet *message"
