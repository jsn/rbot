module Irc

  require 'yaml'
  require 'rbot/messagemapper'

  class BotConfigItem
    attr_reader :type
    attr_reader :desc
    attr_reader :key
    attr_reader :values
    def initialize(key, params)
      @key = key
      if params.has_key? :default
        @default = params[:default]
      else
        @default = false
      end
      @desc = params[:desc]
      @type = params[:type] || String
      @values = params[:values]
      @on_change = params[:on_change]
    end
    def default
      if @default.class == Proc
        @default.call
      else
        @default
      end
    end
    def on_change(newvalue)
      return unless @on_change
      @on_change.call(newvalue)
    end
  end

  # container for bot configuration
  class BotConfig
    class Enum
    end
    class Password
    end
    class Boolean
    end
    
    attr_reader :items
    @@items = Hash.new
    
    def BotConfig.register(key, params)
      unless params.nil? || params.instance_of?(Hash)
        raise ArgumentError,"params must be a hash"
      end
      raise ArgumentError,"params must contain a period" unless key =~ /^.+\..+$/
      @@items[key] = BotConfigItem.new(key, params)
    end

    # currently we store values in a hash but this could be changed in the
    # future. We use hash semantics, however.
    # components that register their config keys and setup defaults are
    # supported via []
    def [](key)
      return @config[key] if @config.has_key?(key)
      return @@items[key].default if @@items.has_key?(key)
      return false
    end
    
    # pass everything through to the hash
    def method_missing(method, *args, &block)
      return @config.send(method, *args, &block)
    end

    def handle_list(m, params)
      modules = []
      if params[:module]
        @@items.each_key do |key|
          mod, name = key.split('.')
          next unless mod == params[:module]
          modules.push name unless modules.include?(name)
        end
        if modules.empty?
          m.reply "no such module #{params[:module]}"
        else
          m.reply "module #{params[:module]} contains: " + modules.join(", ")
        end
      else
        @@items.each_key do |key|
          name = key.split('.').first
          modules.push name unless modules.include?(name)
        end
        m.reply "modules: " + modules.join(", ")
      end
    end

    def handle_get(m, params)
      key = params[:key]
      unless @@items.has_key?(key)
        m.reply "no such config key #{key}"
      end
      value = self[key]
      if @@items[key].type == :array
        value = self[key].join(", ")
      elsif @@items[key].type == :password && !m.private
        value = "******"
      end
      m.reply "#{key}: #{value}"
    end

    def handle_desc(m, params)
      key = params[:key]
      unless @@items.has_key?(key)
        m.reply "no such config key #{key}"
      end
      m.reply "#{key}: #{@@items[key].desc}"
    end

    def handle_unset(m, params)
      key = params[:key]
      unless @@items.has_key?(key)
        m.reply "no such config key #{key}"
      end
      @config.delete(key)
      handle_get(m, params)
    end

    def handle_set(m, params)
      key = params[:key]
      value = params[:value].to_s
      unless @@items.has_key?(key)
        m.reply "no such config key #{key}"
      end
      item = @@items[key]
      puts "item type is #{item.type}"
      case item.type
        when :string
          @config[key] = value
        when :password
          @config[key] = value
        when :integer
          @config[key] = value.to_i
        when :float
          @config[key] = value.to_f
        when :array
          @config[key] = value.split(/,\s*/)
        when :boolean
          if value == "true"
            @config[key] = true
          else
            @config[key] = false
          end
        when :enum
          unless item.values.include?(value)
            m.reply "invalid value #{value}, allowed values are: " + item.values.join(", ")
            return
          end
          @config[key] = value
        else
          puts "ACK, unsupported type #{item.type}"
          exit 2
      end
      item.on_change(@config[key])
      m.okay
    end

    # bot:: parent bot class
    # create a new config hash from #{botclass}/conf.rbot
    def initialize(bot)
      @bot = bot
      @config = Hash.new(false)

      # respond to config messages, to provide runtime configuration
      # management
      # messages will be:
      #  get (implied)
      #  set
      #  unset
      #  and for arrays:
      #    add
      #    remove
      @handler = MessageMapper.new(self)
      @handler.map 'config list :module', :action => 'handle_list',
                   :defaults => {:module => false}
      @handler.map 'config get :key', :action => 'handle_get'
      @handler.map 'config desc :key', :action => 'handle_desc'
      @handler.map 'config describe :key', :action => 'handle_desc'
      @handler.map 'config set :key *value', :action => 'handle_set'
      @handler.map 'config unset :key', :action => 'handle_unset'
      
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

    def privmsg(m)
      @handler.handle(m)
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
          :key => "server.name",
          :type => :string,
        },
        {
          :question => "What port should the bot connect to?",
          :key => "server.port",
          :type => :number,
        },
        {
          :question => "Does this IRC server require a password for access? Leave blank if not.",
          :key => "server.password",
          :type => :password,
        },
        {
          :question => "Would you like rbot to bind to a specific local host or IP? Leave blank if not.",
          :key => "server.bindhost",
          :type => :string,
        },
        {
          :question => "What IRC nickname should the bot attempt to use?",
          :key => "irc.nick",
          :type => :string,
        },
        {
          :question => "What local user should the bot appear to be?",
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
          :key => "core.language",
          :type => :enum,
          :items => Dir.new(Config::DATADIR + "/languages").collect {|f|
            f =~ /\.lang$/ ? f.gsub(/\.lang$/, "") : nil
          }.compact
        },
        {
          :question => "Enter your password for maxing your auth with the bot (used to associate new hostmasks with your owner-status etc)",
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
            print q[:key] + " [#{defaults[key]}]: "
          else
            print q[:key] + " []: "
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
