module Irc

  require 'yaml'

  # container for bot configuration
  class BotConfig

    # currently we store values in a hash but this could be changed in the
    # future. We use hash semantics, however.
    def method_missing(method, *args, &block)
      return @config.send(method, *args, &block)
    end

    # bot:: parent bot class
    # create a new config hash from #{botclass}/conf.rbot
    def initialize(bot)
      @bot = bot
      # some defaults
      @config = Hash.new(false)
      
      @config['server.name'] = "localhost"
      @config['server.port'] = 6667
      @config['server.password'] = false
      @config['server.bindhost'] = false
      @config['server.reconnect_wait'] = 5
      @config['irc.nick'] = "rbot"
      @config['irc.user'] = "rbot"
      @config['irc.join_channels'] = ""
      @config['core.language'] = "english"
      @config['core.save_every'] = 60
      @config['keyword.listen'] = false
      @config['auth.password'] = ""
      @config['server.sendq_delay'] = 2.0
      @config['server.sendq_burst'] = 4
      @config['keyword.address'] = true
      @config['keyword.listen'] = false

      # TODO
      # have this class persist key/values in hash using yaml as it kinda
      # already does.
      # have other users of the class describe config to it on init, like:
      # @config.add(:key => 'server.name', :type => 'string',
      #             :default => 'localhost', :restart => true,
      #             :help => 'irc server to connect to')
      # that way the config module doesn't have to know about all the other
      # classes but can still provide help and defaults.
      # Classes don't have to add keys, they can just use config as a
      # persistent hash, but then they won't be presented by the config
      # module for runtime display/changes.
      # (:restart, if true, makes the bot reply to changes with "this change
      # will take effect after the next restart)
      #  :proc => Proc.new {|newvalue| ...}
      # (:proc, proc to run on change of setting)
      #  or maybe, @config.add_key(...) do |newvalue| .... end
      #  :validate => /regex/
      # (operates on received string before conversion)
      # Special handling for arrays so the config module can be used to
      # add/remove elements as well as changing the whole thing
      # Allow config options to list possible valid values (if type is enum,
      # for example). Then things like the language module can list the
      # available languages for choosing.
      
      if(File.exist?("#{@bot.botclass}/conf.yaml"))
        newconfig = YAML::load_file("#{@bot.botclass}/conf.yaml")
        @config.update(newconfig)
      else
        # first-run wizard!
        wiz = BotConfigWizard.new(@bot)
        newconfig = wiz.run(@config)
        @config.update(newconfig)
      end
    end

    # write current configuration to #{botclass}/conf.rbot
    def save
      Dir.mkdir("#{@bot.botclass}") if(!File.exist?("#{@bot.botclass}"))
      File.open("#{@bot.botclass}/conf.yaml", "w") do |file|
        file.puts @config.to_yaml
      end
    end
  end

  # I don't see a nice way to avoid the first start wizard knowing way too
  # much about other modules etc, because it runs early and stuff it
  # configures is used to initialise the other modules...
  # To minimise this we'll do as little as possible and leave the rest to
  # online modification
  class BotConfigWizard

    # TODO things to configure..
    # config directory (botclass) - people don't realise they should set
    # this. The default... isn't good.
    # users? - default *!*@* to 10
    # levels? - need a way to specify a default level, methinks, for
    # unconfigured items.
    #
    def initialize(bot)
      @bot = bot
      @questions = [
        {
          :question => "What server should the bot connect to?",
          :prompt => "Hostname",
          :key => "server.name",
          :type => :string,
        },
        {
          :question => "What port should the bot connect to?",
          :prompt => "Port",
          :key => "server.port",
          :type => :number,
        },
        {
          :question => "Does this IRC server require a password for access? Leave blank if not.",
          :prompt => "Password",
          :key => "server.password",
          :type => :password,
        },
        {
          :question => "Would you like rbot to bind to a specific local host or IP? Leave blank if not.",
          :prompt => "Local bind",
          :key => "server.bindhost",
          :type => :string,
        },
        {
          :question => "What IRC nickname should the bot attempt to use?",
          :prompt => "Nick",
          :key => "irc.nick",
          :type => :string,
        },
        {
          :question => "What local user should the bot appear to be?",
          :prompt => "User",
          :key => "irc.user",
          :type => :string,
        },
        {
          :question => "What channels should the bot always join at startup? List multiple channels using commas to separate. If a channel requires a password, use a space after the channel name. e.g: '#chan1, #chan2, #secretchan secritpass, #chan3'",
          :prompt => "Channels",
          :key => "irc.join_channels",
          :type => :string,
        },
        {
          :question => "Which language file should the bot use?",
          :prompt => "Language",
          :key => "core.language",
          :type => :enum,
          :items => Dir.new(Config::DATADIR + "/languages").collect {|f|
            f =~ /\.lang$/ ? f.gsub(/\.lang$/, "") : nil
          }.compact
        },
        {
          :question => "Enter your password for maxing your auth with the bot (used to associate new hostmasks with your owner-status etc)",
          :prompt => "Password",
          :key => "auth.password",
          :type => :password,
        },
      ]
    end
    
    def run(defaults)
      config = defaults.clone
      puts "First time rbot configuration wizard"
      puts "===================================="
      puts "This is the first time you have run rbot with a config directory of:"
      puts @bot.botclass
      puts "This wizard will ask you a few questions to get you started."
      puts "The rest of rbot's configuration can be manipulated via IRC once"
      puts "rbot is connected and you are auth'd."
      puts "-----------------------------------"

      @questions.each do |q|
        puts q[:question]
        begin
          key = q[:key]
          if q[:type] == :enum
            puts "valid values are: " + q[:items].join(", ")
          end
          if (defaults.has_key?(key))
            print q[:prompt] + " [#{defaults[key]}]: "
          else
            print q[:prompt] + " []: "
          end
          response = STDIN.gets
          response.chop!
          response = defaults[key] if response == "" && defaults.has_key?(key)
          case q[:type]
            when :string
            when :number
              raise "value '#{response}' is not a number" unless (response.class == Fixnum || response =~ /^\d+$/)
              response = response.to_i
            when :password
            when :enum
              raise "selected value '#{response}' is not one of the valid values" unless q[:items].include?(response)
          end
          config[key] = response
          puts "configured #{key} => #{config[key]}"
          puts "-----------------------------------"
        rescue RuntimeError => e
          puts e.message
          retry
        end
      end
      return config
    end
  end
end
