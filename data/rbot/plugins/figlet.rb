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

  Config.register Config::StringValue.new('toilet.path',
     :default => '/usr/bin/toilet',
     :desc => _('Path to the toilet program'),
     :on_change => Proc.new { |bot, v| bot.plugins['figlet'].test_toilet })

  Config.register Config::StringValue.new('toilet.font',
     :default => 'rectangles',
     :desc => _('toilet font to use'),
     :validate => Proc.new { |v| v !~ /\s|`/ },
     :on_change => Proc.new { |bot, v| bot.plugins['figlet'].test_toilet })

  Config.register Config::ArrayValue.new('toilet.filters',
     :default => [],
     :desc => _('toilet filters to use (e.g. gay, metal)'),
     :validate => Proc.new { |v| v !~ /\s|`/ },
     :on_change => Proc.new { |bot, v| bot.plugins['figlet'].test_toilet })

  def figlet_path
    @bot.config['figlet.path']
  end

  def toilet_path
    @bot.config['toilet.path']
  end

  def figlet_font
    @bot.config['figlet.font']
  end

  def toilet_font
    @bot.config['toilet.font']
  end

  def toilet_filters
    @bot.config['toilet.filters']
  end

  def test_figlet
    #check that figlet is present
    @has[:figlet] = File.exist?(figlet_path)

    # check that figlet actually has the font installed
    @has[:figlet_font] = !!system("#{figlet_path} -f #{figlet_font} test test test")

    # set the commandline params
    @params[:figlet] = ['-k', '-w', MAX_WIDTH.to_s, '-C', 'utf8']

    # add the font from DEFAULT_FONTS to the cmdline (if figlet has that font)
    @params[:figlet] += ['-f', figlet_font] if @has_figlet_font
  end

  def test_toilet
    #check that toilet is present
    @has[:toilet] = File.exist?(toilet_path)

    # check that toilet actually has the font installed
    @has[:toilet_font] = !!system("#{toilet_path} -f #{toilet_font} test test test")

    # set the commandline params
    @params[:toilet] = ['-k', '-w', MAX_WIDTH.to_s, '-E', 'utf8', '--irc']

    # add the font from DEFAULT_FONTS to the cmdline (if toilet has that font)
    @params[:toilet] += ['-f', toilet_font] if @has_toilet_font

    # add the filters, if any
    toilet_filters.each { |f| @params[:toilet] += ['-F', f.dup] }
  end

  def initialize
    super

    @has = {}
    @params = {}

    # test for figlet and font presence
    test_figlet
    # ditto for toilet
    test_toilet
  end

  def help(plugin, topic="")
    "figlet|toilet <message> => print using figlet or toilet"
  end

  def figlet(m, params)
    key = m.plugin.intern
    unless @has[key]
      m.reply("%{cmd} couldn't be found. if it's installed, you should set the %{cmd}.path config key to its path" % {
        :cmd => key
      })
      return
    end

    message = params[:message].to_s
    if message =~ /^-/
      m.reply "the message can't start with a - sign"
      return
    end

    # collect the parameters to pass to safe_exec
    exec_params = [send(:"#{m.plugin}_path")] + @params[key] + [message]

    # run the program
    m.reply Utils.safe_exec(*exec_params), :max_lines => 0
  end
  alias :toilet :figlet

end

plugin = FigletPlugin.new
plugin.map "figlet *message"
plugin.map "toilet *message"
