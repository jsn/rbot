require 'singleton'

require 'yaml'

unless YAML.respond_to?(:load_file)
  def YAML.load_file( filepath )
    File.open( filepath ) do |f|
      YAML::load( f )
    end
  end
end


module Irc

class Bot
module Config
  class Value
    # allow the definition order to be preserved so that sorting by
    # definition order is possible. The Wizard does this to allow
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
    attr_reader :auth_path
    def initialize(key, params)
      @manager = Config.manager
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
      @auth_path = "config::key::#{key.sub('.','::')}"
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
      @manager.changed = true
      @on_change.call(@manager.bot, value) if on_change && @on_change
      return self
    end
    def unset
      @manager.config.delete(@key)
      @manager.changed = true
      @on_change.call(@manager.bot, value) if @on_change
      return self
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

    protected
    def validate(val, validator  = @validate)
      case validator
      when false, nil
        return true
      when Proc
        return validator.call(val)
      when Regexp
        raise ArgumentError, "validation via Regexp only supported for strings!" unless String === val
        return validator.match(val)
      else
        raise ArgumentError, "validation type #{validator.class} not supported"
      end
    end
  end

  class StringValue < Value
  end

  class BooleanValue < Value
    def parse(string)
      return true if string == "true"
      return false if string == "false"
      if string =~ /^-?\d+$/
        return string.to_i != 0
      end
      raise ArgumentError, "#{string} does not match either 'true' or 'false', and it's not an integer either"
    end
    def get
      r = super
      if r.kind_of?(Integer)
        return r != 0
      else
        return r
      end
    end
  end

  class IntegerValue < Value
    def parse(string)
      return 1 if string == "true"
      return 0 if string == "false"
      raise ArgumentError, "not an integer: #{string}" unless string =~ /^-?\d+$/
      string.to_i
    end
    def get
      r = super
      if r.kind_of?(Integer)
        return r
      else
        return r ? 1 : 0
      end
    end
  end

  class FloatValue < Value
    def parse(string)
      raise ArgumentError, "not a float #{string}" unless string =~ /^-?[\d.]+$/
      string.to_f
    end
  end

  class ArrayValue < Value
    def initialize(key, params)
      super
      @validate_item = params[:validate_item]
      @validate ||= Proc.new do |v|
        !v.find { |i| !validate_item(i) }
      end
    end

    def validate_item(item)
      validate(item, @validate_item)
    end

    def parse(string)
      string.split(/,\s+/)
    end
    def to_s
      get.join(", ")
    end
    def add(val)
      newval = self.get.dup
      unless newval.include? val
        newval << val
        validate_item(val) or raise ArgumentError, "invalid item: #{val}"
        validate(newval) or raise ArgumentError, "invalid value: #{newval.to_s}"
        set(newval)
      end
    end
    def rm(val)
      curval = self.get
      raise ArgumentError, "value #{val} not present" unless curval.include?(val)
      set(curval - [val])
    end
  end

  class EnumValue < Value
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
      _("%{desc} [valid values are: %{values}]") % {:desc => @desc, :values => values.join(', ')}
    end
  end

  # container for bot configuration
  class ManagerClass

    include Singleton

    attr_reader :bot
    attr_reader :items
    attr_reader :config
    attr_accessor :changed

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

      @changed = false
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
      Wizard.new(@bot).run
      # save newly created config
      @changed = true
      save
    end

    def register(item)
      unless item.kind_of?(Value)
        raise ArgumentError,"item must be an Irc::Bot::Config::Value"
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
        warning _("Unregistered lookup #{key.to_sym.inspect}")
        return @config[key.to_sym]
      end
      return false
    end

    def []=(key, value)
      return @items[key.to_sym].set(value) if @items.has_key?(key.to_sym)
      if @config.has_key?(key.to_sym)
        warning _("Unregistered lookup #{key.to_sym.inspect}")
        return @config[key.to_sym] = value
      end
    end

    # pass everything else through to the hash
    def method_missing(method, *args, &block)
      return @config.send(method, *args, &block)
    end

    # write current configuration to #{botclass}/conf.yaml
    def save
      if not @changed
        debug "Not writing conf.yaml (unchanged)"
        return
      end
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
        @changed = false
      rescue => e
        error "failed to write configuration file conf.yaml! #{$!}"
        error "#{e.class}: #{e}"
        error e.backtrace.join("\n")
      end
    end
  end

  # Returns the only Irc::Bot::Config::ManagerClass
  #
  def Config.manager
    return ManagerClass.instance
  end

  # Register a config value
  def Config.register(item)
    Config.manager.register(item)
  end

  class Wizard
    def initialize(bot)
      @bot = bot
      @manager = Config.manager
      @questions = @manager.items.values.find_all {|i| i.wizard }
    end

    def run()
      puts _("First time rbot configuration wizard")
      puts "===================================="
      puts _("This is the first time you have run rbot with a config directory of: #{@bot.botclass}")
      puts _("This wizard will ask you a few questions to get you started.")
      puts _("The rest of rbot's configuration can be manipulated via IRC once rbot is connected and you are auth'd.")
      puts "-----------------------------------"

      return unless @questions
      @questions.sort{|a,b| a.order <=> b.order }.each do |q|
        puts _(q.desc)
        begin
          print q.key.to_s + " [#{q.to_s}]: "
          response = STDIN.gets
          response.chop!
          unless response.empty?
            q.set_string response, false
          end
          puts _("configured #{q.key} => #{q.to_s}")
          puts "-----------------------------------"
        rescue ArgumentError => e
          puts _("failed to set #{q.key}: #{e.message}")
          retry
        end
      end
    end
  end

end
end
end
