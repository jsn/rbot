module Irc

  require 'yaml'
  require 'rbot/messagemapper'

  unless YAML.respond_to?(:load_file)
    module YAML
      def YAML.load_file( filepath )
        File.open( filepath ) do |f|
          YAML::load( f )
        end
      end
    end
  end

  class BotConfigValue
    # allow the definition order to be preserved so that sorting by
    # definition order is possible. The BotConfigWizard does this to allow
    # the :wizard questions to be in a sensible order.
    @@order = 0
    attr_reader :type
    attr_reader :desc
    attr_reader :key
    attr_reader :wizard
    attr_reader :requires_restart
    attr_reader :order
    def initialize(key, params)
      unless key =~ /^.+\..+$/
        raise ArgumentError,"key must be of the form 'module.name'"
      end
      @order = @@order
      @@order += 1
      @key = key
      if params.has_key? :default
        @default = params[:default]
      else
        @default = false
      end
      @desc = params[:desc]
      @type = params[:type] || String
      @on_change = params[:on_change]
      @validate = params[:validate]
      @wizard = params[:wizard]
      @requires_restart = params[:requires_restart]
    end
    def default
      if @default.instance_of?(Proc)
        @default.call
      else
        @default
      end
    end
    def get
      return BotConfig.config[@key] if BotConfig.config.has_key?(@key)
      return @default
    end
    alias :value :get
    def set(value, on_change = true)
      BotConfig.config[@key] = value
      @on_change.call(BotConfig.bot, value) if on_change && @on_change
    end
    def unset
      BotConfig.config.delete(@key)
    end

    # set string will raise ArgumentErrors on failed parse/validate
    def set_string(string, on_change = true)
      value = parse string
      if validate value
        set value, on_change
      else
        raise ArgumentError, "invalid value: #{string}"
      end
    end
    
    # override this. the default will work for strings only
    def parse(string)
      string
    end

    def to_s
      get.to_s
    end

    private
    def validate(value)
      return true unless @validate
      if @validate.instance_of?(Proc)
        return @validate.call(value)
      elsif @validate.instance_of?(Regexp)
        raise ArgumentError, "validation via Regexp only supported for strings!" unless value.instance_of? String
        return @validate.match(value)
      else
        raise ArgumentError, "validation type #{@validate.class} not supported"
      end
    end
  end

  class BotConfigStringValue < BotConfigValue
  end
  class BotConfigBooleanValue < BotConfigValue
    def parse(string)
      return true if string == "true"
      return false if string == "false"
      raise ArgumentError, "#{string} does not match either 'true' or 'false'"
    end
  end
  class BotConfigIntegerValue < BotConfigValue
    def parse(string)
      raise ArgumentError, "not an integer: #{string}" unless string =~ /^-?\d+$/
      string.to_i
    end
  end
  class BotConfigFloatValue < BotConfigValue
    def parse(string)
      raise ArgumentError, "not a float #{string}" unless string =~ /^-?[\d.]+$/
      string.to_f
    end
  end
  class BotConfigArrayValue < BotConfigValue
    def parse(string)
      string.split(/,\s+/)
    end
    def to_s
      get.join(", ")
    end
  end
  class BotConfigEnumValue < BotConfigValue
    def initialize(key, params)
      super
      @values = params[:values]
    end
    def values
      if @values.instance_of?(Proc)
        return @values.call(BotConfig.bot)
      else
        return @values
      end
    end
    def parse(string)
      unless @values.include?(string)
        raise ArgumentError, "invalid value #{string}, allowed values are: " + @values.join(", ")
      end
      string
    end
    def desc
      "#{@desc} [valid values are: " + values.join(", ") + "]"
    end
  end

  # container for bot configuration
  class BotConfig
    # Array of registered BotConfigValues for defaults, types and help
    @@items = Hash.new
    def BotConfig.items
      @@items
    end
    # Hash containing key => value pairs for lookup and serialisation
    @@config = Hash.new(false)
    def BotConfig.config
      @@config
    end
    def BotConfig.bot
      @@bot
    end
    
    def BotConfig.register(item)
      unless item.kind_of?(BotConfigValue)
        raise ArgumentError,"item must be a BotConfigValue"
      end
      @@items[item.key] = item
    end

    # currently we store values in a hash but this could be changed in the
    # future. We use hash semantics, however.
    # components that register their config keys and setup defaults are
    # supported via []
    def [](key)
      return @@items[key].value if @@items.has_key?(key)
      # try to still support unregistered lookups
      return @@config[key] if @@config.has_key?(key)
      return false
    end

    # TODO should I implement this via BotConfigValue or leave it direct?
    #    def []=(key, value)
    #    end
    
    # pass everything else through to the hash
    def method_missing(method, *args, &block)
      return @@config.send(method, *args, &block)
    end

    def handle_list(m, params)
      modules = []
      if params[:module]
        @@items.each_key do |key|
          mod, name = key.split('.')
          next unless mod == params[:module]
          modules.push key unless modules.include?(name)
        end
        if modules.empty?
          m.reply "no such module #{params[:module]}"
        else
          m.reply modules.join(", ")
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
        return
      end
      value = @@items[key].to_s
      m.reply "#{key}: #{value}"
    end

    def handle_desc(m, params)
      key = params[:key]
      unless @@items.has_key?(key)
        m.reply "no such config key #{key}"
      end
      puts @@items[key].inspect
      m.reply "#{key}: #{@@items[key].desc}"
    end

    def handle_unset(m, params)
      key = params[:key]
      unless @@items.has_key?(key)
        m.reply "no such config key #{key}"
      end
      @@items[key].unset
      handle_get(m, params)
    end

    def handle_set(m, params)
      key = params[:key]
      value = params[:value].to_s
      unless @@items.has_key?(key)
        m.reply "no such config key #{key}"
        return
      end
      begin
        @@items[key].set_string(value)
      rescue ArgumentError => e
        m.reply "failed to set #{key}: #{e.message}"
        return
      end
      if @@items[key].requires_restart
        m.reply "this config change will take effect on the next restart"
      else
        m.okay
      end
    end

    def handle_help(m, params)
      topic = params[:topic]
      case topic
      when false
        m.reply "config module - bot configuration. usage: list, desc, get, set, unset"
      when "list"
        m.reply "config list => list configuration modules, config list <module> => list configuration keys for module <module>"
      when "get"
        m.reply "config get <key> => get configuration value for key <key>"
      when "unset"
        m.reply "reset key <key> to the default"
      when "set"
        m.reply "config set <key> <value> => set configuration value for key <key> to <value>"
      when "desc"
        m.reply "config desc <key> => describe what key <key> configures"
      else
        m.reply "no help for config #{topic}"
      end
    end
    def usage(m,params)
      m.reply "incorrect usage, try '#{@@bot.nick}: help config'"
    end

    # bot:: parent bot class
    # create a new config hash from #{botclass}/conf.rbot
    def initialize(bot)
      @@bot = bot

      # respond to config messages, to provide runtime configuration
      # management
      # messages will be:
      #  get
      #  set
      #  unset
      #  desc
      #  and for arrays:
      #    add TODO
      #    remove TODO
      @handler = MessageMapper.new(self)
      @handler.map 'config list :module', :action => 'handle_list',
                   :defaults => {:module => false}
      @handler.map 'config get :key', :action => 'handle_get'
      @handler.map 'config desc :key', :action => 'handle_desc'
      @handler.map 'config describe :key', :action => 'handle_desc'
      @handler.map 'config set :key *value', :action => 'handle_set'
      @handler.map 'config unset :key', :action => 'handle_unset'
      @handler.map 'config help :topic', :action => 'handle_help',
                   :defaults => {:topic => false}
      @handler.map 'help config :topic', :action => 'handle_help',
                   :defaults => {:topic => false}
      
      if(File.exist?("#{@@bot.botclass}/conf.yaml"))
        newconfig = YAML::load_file("#{@@bot.botclass}/conf.yaml")
        @@config.update newconfig
      else
        # first-run wizard!
        BotConfigWizard.new(@@bot).run
        # save newly created config
        save
      end
    end

    # write current configuration to #{botclass}/conf.rbot
    def save
      File.open("#{@@bot.botclass}/conf.yaml", "w") do |file|
        file.puts @@config.to_yaml
      end
    end

    def privmsg(m)
      @handler.handle(m)
    end
  end

  class BotConfigWizard
    def initialize(bot)
      @bot = bot
      @questions = BotConfig.items.values.find_all {|i| i.wizard }
    end
    
    def run()
      puts "First time rbot configuration wizard"
      puts "===================================="
      puts "This is the first time you have run rbot with a config directory of:"
      puts @bot.botclass
      puts "This wizard will ask you a few questions to get you started."
      puts "The rest of rbot's configuration can be manipulated via IRC once"
      puts "rbot is connected and you are auth'd."
      puts "-----------------------------------"

      return unless @questions
      @questions.sort{|a,b| a.order <=> b.order }.each do |q|
        puts q.desc
        begin
          print q.key + " [#{q.to_s}]: "
          response = STDIN.gets
          response.chop!
          unless response.empty?
            q.set_string response, false
          end
          puts "configured #{q.key} => #{q.to_s}"
          puts "-----------------------------------"
        rescue ArgumentError => e
          puts "failed to set #{q.key}: #{e.message}"
          retry
        end
      end
    end
  end
end
