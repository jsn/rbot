require 'singleton'

module Irc

  require 'yaml'

  unless YAML.respond_to?(:load_file)
      def YAML.load_file( filepath )
        File.open( filepath ) do |f|
          YAML::load( f )
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
    attr_reader :requires_rescan
    attr_reader :order
    attr_reader :manager
    def initialize(key, params)
      @manager = BotConfig::configmanager
      # Keys must be in the form 'module.name'.
      # They will be internally passed around as symbols,
      # but we accept them both in string and symbol form.
      unless key.to_s =~ /^.+\..+$/
        raise ArgumentError,"key must be of the form 'module.name'"
      end
      @order = @@order
      @@order += 1
      @key = key.to_sym
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
      @requires_rescan = params[:requires_rescan]
    end
    def default
      if @default.instance_of?(Proc)
        @default.call
      else
        @default
      end
    end
    def get
      return @manager.config[@key] if @manager.config.has_key?(@key)
      return @default
    end
    alias :value :get
    def set(value, on_change = true)
      @manager.config[@key] = value
      @on_change.call(@manager.bot, value) if on_change && @on_change
    end
    def unset
      @manager.config.delete(@key)
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
    def add(val)
      curval = self.get
      set(curval + [val]) unless curval.include?(val)
    end
    def rm(val)
      curval = self.get
      raise ArgumentError, "value #{val} not present" unless curval.include?(val)
      set(curval - [val])
    end
  end

  class BotConfigEnumValue < BotConfigValue
    def initialize(key, params)
      super
      @values = params[:values]
    end
    def values
      if @values.instance_of?(Proc)
        return @values.call(@manager.bot)
      else
        return @values
      end
    end
    def parse(string)
      unless values.include?(string)
        raise ArgumentError, "invalid value #{string}, allowed values are: " + values.join(", ")
      end
      string
    end
    def desc
      "#{@desc} [valid values are: " + values.join(", ") + "]"
    end
  end

  # container for bot configuration
  class BotConfigManagerClass

    include Singleton

    attr_reader :bot
    attr_reader :items
    attr_reader :config

    def initialize
      bot_associate(nil,true)
    end

    def reset_config
      @items = Hash.new
      @config = Hash.new(false)
    end

    # Associate with bot _bot_
    def bot_associate(bot, reset=false)
      reset_config if reset
      @bot = bot
      return unless @bot

      if(File.exist?("#{@bot.botclass}/conf.yaml"))
        begin
          newconfig = YAML::load_file("#{@bot.botclass}/conf.yaml")
          newconfig.each { |key, val|
            @config[key.to_sym] = val
          }
          return
        rescue
          error "failed to read conf.yaml: #{$!}"
        end
      end
      # if we got here, we need to run the first-run wizard
      BotConfigWizard.new(@bot).run
      # save newly created config
      save
    end

    def register(item)
      unless item.kind_of?(BotConfigValue)
        raise ArgumentError,"item must be a BotConfigValue"
      end
      @items[item.key] = item
    end

    # currently we store values in a hash but this could be changed in the
    # future. We use hash semantics, however.
    # components that register their config keys and setup defaults are
    # supported via []
    def [](key)
      # return @items[key].value if @items.has_key?(key)
      return @items[key.to_sym].value if @items.has_key?(key.to_sym)
      # try to still support unregistered lookups
      # but warn about them
      #      if @config.has_key?(key)
      #        warning "Unregistered lookup #{key.inspect}"
      #        return @config[key]
      #      end
      if @config.has_key?(key.to_sym)
        warning "Unregistered lookup #{key.to_sym.inspect}"
        return @config[key.to_sym]
      end
      return false
    end

    # TODO should I implement this via BotConfigValue or leave it direct?
    #    def []=(key, value)
    #    end

    # pass everything else through to the hash
    def method_missing(method, *args, &block)
      return @config.send(method, *args, &block)
    end

    # write current configuration to #{botclass}/conf.yaml
    def save
      begin
        debug "Writing new conf.yaml ..."
        File.open("#{@bot.botclass}/conf.yaml.new", "w") do |file|
          savehash = {}
          @config.each { |key, val|
            savehash[key.to_s] = val
          }
          file.puts savehash.to_yaml
        end
        debug "Officializing conf.yaml ..."
        File.rename("#{@bot.botclass}/conf.yaml.new",
                    "#{@bot.botclass}/conf.yaml")
      rescue => e
        error "failed to write configuration file conf.yaml! #{$!}"
        error "#{e.class}: #{e}"
        error e.backtrace.join("\n")
      end
    end
  end

  module BotConfig
    # Returns the only BotConfigManagerClass
    #
    def BotConfig.configmanager
      return BotConfigManagerClass.instance
    end

    # Register a config value
    def BotConfig.register(item)
      BotConfig.configmanager.register(item)
    end
  end

  class BotConfigWizard
    def initialize(bot)
      @bot = bot
      @manager = BotConfig::configmanager
      @questions = @manager.items.values.find_all {|i| i.wizard }
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
          print q.key.to_s + " [#{q.to_s}]: "
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
