#-- vim:sw=2:et
#++
#
# :title: Figlet plugin

class FigletPlugin < Plugin
  MAX_WIDTH=68

  Config.register Config::StringValue.new('figlet.path',
     :default => '/usr/bin/figlet',
     :desc => _('Path to the figlet program'),
     :on_change => Proc.new { |bot, v| bot.plugins['figlet'].test_figlet })

  Config.register Config::StringValue.new('figlet.font',
     :default => 'rectangles',
     :desc => _('figlet font to use'),
     :validate => Proc.new { |v| v !~ /\s|`/ },
     :on_change => Proc.new { |bot, v| bot.plugins['figlet'].test_figlet })

  def figlet_path
    @bot.config['figlet.path']
  end

  def figlet_font
    @bot.config['figlet.font']
  end

  attr_reader :has_figlet
  attr_reader :has_font

  def test_figlet
    #check that figlet is present
    @has_figlet = File.exist?(figlet_path)

    # check that figlet actually has the font installed
    @has_font = !!system("#{figlet_path} -f #{figlet_font} test test test")

    # set the commandline params
    @figlet_params = ['-k', '-w', MAX_WIDTH.to_s, '-C', 'utf8']

    # add the font from DEFAULT_FONTS to the cmdline (if figlet has that font)
    @figlet_params += ['-f', figlet_font] if @has_font
  end

  def initialize
    super

    # test for figlet and font presence
    test_figlet
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
