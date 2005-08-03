require 'rbot/dbhash'

module Irc

  # this is the backend of the RegistryAccessor class, which ties it to a
  # DBHash object called plugin_registry(.db). All methods are delegated to
  # the DBHash.
  class BotRegistry
    def initialize(bot)
      @bot = bot
      upgrade_data
      @db = DBTree.new @bot, "plugin_registry"
    end

    # delegation hack
    def method_missing(method, *args, &block)
      @db.send(method, *args, &block)
    end

    # check for older versions of rbot with data formats that require updating
    # NB this function is called _early_ in init(), pretty much all you have to
    # work with is @bot.botclass.
    def upgrade_data
      if File.exist?("#{@bot.botclass}/registry.db")
        puts "upgrading old-style (rbot 0.9.5 or earlier) plugin registry to new format"
        old = BDB::Hash.open "#{@bot.botclass}/registry.db", nil, 
                             "r+", 0600, "set_pagesize" => 1024,
                             "set_cachesize" => [0, 32 * 1024, 0]
        new = BDB::CIBtree.open "#{@bot.botclass}/plugin_registry.db", nil, 
                                BDB::CREATE | BDB::EXCL | BDB::TRUNCATE,
                                0600, "set_pagesize" => 1024,
                                "set_cachesize" => [0, 32 * 1024, 0]
        old.each {|k,v|
          new[k] = v
        }
        old.close
        new.close
        File.delete("#{@bot.botclass}/registry.db")
      end
    end
  end

  # This class provides persistent storage for plugins via a hash interface.
  # The default mode is an object store, so you can store ruby objects and
  # reference them with hash keys. This is because the default store/restore
  # methods of the plugins' RegistryAccessor are calls to Marshal.dump and
  # Marshal.restore,
  # for example:
  #   blah = Hash.new
  #   blah[:foo] = "fum"
  #   @registry[:blah] = blah
  # then, even after the bot is shut down and disconnected, on the next run you
  # can access the blah object as it was, with:
  #   blah = @registry[:blah]
  # The registry can of course be used to store simple strings, fixnums, etc as
  # well, and should be useful to store or cache plugin data or dynamic plugin
  # configuration. 
  #
  # WARNING:
  # in object store mode, don't make the mistake of treating it like a live
  # object, e.g. (using the example above)
  #   @registry[:blah][:foo] = "flump"
  # will NOT modify the object in the registry - remember that BotRegistry#[]
  # returns a Marshal.restore'd object, the object you just modified in place
  # will disappear. You would need to:
  #   blah = @registry[:blah]
  #   blah[:foo] = "flump"
  #   @registry[:blah] = blah

  # If you don't need to store objects, and strictly want a persistant hash of
  # strings, you can override the store/restore methods to suit your needs, for
  # example (in your plugin):
  #   def initialize
  #     class << @registry
  #       def store(val)
  #         val
  #       end
  #       def restore(val)
  #         val
  #       end
  #     end
  #   end
  # Your plugins section of the registry is private, it has its own namespace
  # (derived from the plugin's class name, so change it and lose your data).
  # Calls to registry.each etc, will only iterate over your namespace.
  class BotRegistryAccessor
    # plugins don't call this - a BotRegistryAccessor is created for them and
    # is accessible via @registry.
    def initialize(bot, prefix)
      @bot = bot
      @registry = @bot.registry
      @orig_prefix = prefix
      @prefix = prefix + "/"
      @default = nil
      # debug "initializing registry accessor with prefix #{@prefix}"
    end

    # use this to chop up your namespace into bits, so you can keep and
    # reference separate object stores under the same registry
    def sub_registry(prefix)
      return BotRegistryAccessor.new(@bot, @orig_prefix + "+" + prefix)
    end

    # convert value to string form for storing in the registry
    # defaults to Marshal.dump(val) but you can override this in your module's
    # registry object to use any method you like.
    # For example, if you always just handle strings use:
    #   def store(val)
    #     val
    #   end
    def store(val)
      Marshal.dump(val)
    end

    # restores object from string form, restore(store(val)) must return val.
    # If you override store, you should override restore to reverse the
    # action.
    # For example, if you always just handle strings use:
    #   def restore(val)
    #     val
    #   end
    def restore(val)
      Marshal.restore(val)
    end

    # lookup a key in the registry
    def [](key)
      if @registry.has_key?(@prefix + key)
        return restore(@registry[@prefix + key])
      elsif @default != nil
        return restore(@default)
      else
        return nil
      end
    end

    # set a key in the registry
    def []=(key,value)
      @registry[@prefix + key] = store(value)
    end

    # set the default value for registry lookups, if the key sought is not
    # found, the default will be returned. The default default (har) is nil.
    def set_default (default)
      @default = store(default)
    end

    # just like Hash#each
    def each(&block)
      @registry.each {|key,value|
        if key.gsub!(/^#{Regexp.escape(@prefix)}/, "")
          block.call(key, restore(value))
        end
      }
    end
    
    # just like Hash#each_key
    def each_key(&block)
      @registry.each {|key, value|
        if key.gsub!(/^#{Regexp.escape(@prefix)}/, "")
          block.call(key)
        end
      }
    end
    
    # just like Hash#each_value
    def each_value(&block)
      @registry.each {|key, value|
        if key =~ /^#{Regexp.escape(@prefix)}/
          block.call(restore(value))
        end
      }
    end

    # just like Hash#has_key?
    def has_key?(key)
      return @registry.has_key?(@prefix + key)
    end
    alias include? has_key?
    alias member? has_key?

    # just like Hash#has_both?
    def has_both?(key, value)
      return @registry.has_both?(@prefix + key, store(value))
    end
    
    # just like Hash#has_value?
    def has_value?(value)
      return @registry.has_value?(store(value))
    end

    # just like Hash#index?
    def index(value)
      ind = @registry.index(store(value))
      if ind && ind.gsub!(/^#{Regexp.escape(@prefix)}/, "")
        return ind
      else
        return nil
      end
    end
    
    # delete a key from the registry
    def delete(key)
      return @registry.delete(@prefix + key)
    end

    # returns a list of your keys
    def keys
      return @registry.keys.collect {|key|
        if key.gsub!(/^#{Regexp.escape(@prefix)}/, "")  
          key
        else
          nil
        end
      }.compact
    end

    # Return an array of all associations [key, value] in your namespace
    def to_a
      ret = Array.new
      @registry.each {|key, value|
        if key.gsub!(/^#{Regexp.escape(@prefix)}/, "")
          ret << [key, restore(value)]
        end
      }
      return ret
    end
    
    # Return an hash of all associations {key => value} in your namespace
    def to_hash
      ret = Hash.new
      @registry.each {|key, value|
        if key.gsub!(/^#{Regexp.escape(@prefix)}/, "")
          ret[key] = restore(value)
        end
      }
      return ret
    end

    # empties the registry (restricted to your namespace)
    def clear
      @registry.each_key {|key|
        if key =~ /^#{Regexp.escape(@prefix)}/
          @registry.delete(key)
        end
      }
    end
    alias truncate clear

    # returns an array of the values in your namespace of the registry
    def values
      ret = Array.new
      self.each {|k,v|
        ret << restore(v)
      }
      return ret
    end

    # returns the number of keys in your registry namespace
    def length
      self.keys.length
    end
    alias size length

    def flush
      @registry.flush
    end
    
  end

end
