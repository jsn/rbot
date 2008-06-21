#-- vim:sw=2:et
#++
#
# :title: Figlet plugin

class FigletPlugin < Plugin
  DEFAULT_FONTS = ['rectangles', 'smslant']
  MAX_WIDTH=68

  Config.register Config::StringValue.new('figlet.path',
     :default => '/usr/bin/figlet',
     :desc => _('Path to the figlet program'),
     :on_change => Proc.new { |bot, v| bot.plugins['figlet'].test_figlet })

  def figlet_path
    @bot.config['figlet.path']
  end

  attr_reader :has_figlet
  attr_accessor :figlet_font

  def test_figlet
    #check that figlet is present
    @has_figlet = File.exist?(figlet_path)

    # check that figlet actually has the font installed
    @figlet_font = nil
    for fontname in DEFAULT_FONTS
      # check if figlet can render this font properly
      if system("#{figlet_path} -f #{fontname} test test test")
        @figlet_font = fontname
        break
      end
    end
  end

  def initialize
    super


    # test for figlet and font presence
    test_figlet

    # set the commandline params
    @figlet_params = ['-k', '-w', MAX_WIDTH.to_s]

    # add the font from DEFAULT_FONTS to the cmdline (if figlet has that font)
    @figlet_params += ['-f', @figlet_font] if @figlet_font

  end

  def help(plugin, topic="")
    "figlet <message> => print using figlet"
  end

  def figlet(m, params)
    unless @has_figlet
      m.reply "figlet couldn't be found. if it's installed, you should set the figlet.path config key to its path"
      return
    end

    message = params[:message].to_s
    if message =~ /^-/
      m.reply "the message can't start with a - sign"
      return
    end

    # collect the parameters to pass to safe_exec
    exec_params = [figlet_path] + @figlet_params + [message]

    # run figlet
    m.reply Utils.safe_exec(*exec_params), :max_lines => 0
  end

end

plugin = FigletPlugin.new
plugin.map "figlet *message"
