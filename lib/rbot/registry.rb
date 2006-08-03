require 'rbot/dbhash'

module Irc

  # this class is now used purely for upgrading from prior versions of rbot
  # the new registry is split into multiple DBHash objects, one per plugin
  class BotRegistry
    def initialize(bot)
      @bot = bot
      upgrade_data
      upgrade_data2
    end

    # check for older versions of rbot with data formats that require updating
    # NB this function is called _early_ in init(), pretty much all you have to
    # work with is @bot.botclass.
    def upgrade_data
      if File.exist?("#{@bot.botclass}/registry.db")
        log "upgrading old-style (rbot 0.9.5 or earlier) plugin registry to new format"
        old = BDB::Hash.open("#{@bot.botclass}/registry.db", nil,
                             "r+", 0600)
        new = BDB::CIBtree.open("#{@bot.botclass}/plugin_registry.db", nil,
                                BDB::CREATE | BDB::EXCL,
                                0600)
        old.each {|k,v|
          new[k] = v
        }
        old.close
        new.close
        File.rename("#{@bot.botclass}/registry.db", "#{@bot.botclass}/registry.db.old")
      end
    end

    def upgrade_data2
      if File.exist?("#{@bot.botclass}/plugin_registry.db")
        Dir.mkdir("#{@bot.botclass}/registry") unless File.exist?("#{@bot.botclass}/registry")
        env = BDB::Env.open("#{@bot.botclass}", BDB::INIT_TRANSACTION | BDB::CREATE | BDB::RECOVER )
        dbs = Hash.new
        log "upgrading previous (rbot 0.9.9 or earlier) plugin registry to new split format"
        old = BDB::CIBtree.open("#{@bot.botclass}/plugin_registry.db", nil,
          "r+", 0600, "env" => env)
        old.each {|k,v|
          prefix,key = k.split("/", 2)
          prefix.downcase!
          # subregistries were split with a +, now they are in separate folders
          if prefix.gsub!(/\+/, "/")
            # Ok, this code needs to be put in the db opening routines
            dirs = File.dirname("#{@bot.botclass}/registry/#{prefix}.db").split("/")
            dirs.length.times { |i|
              dir = dirs[0,i+1].join("/")+"/"
              unless File.exist?(dir)
                log "creating subregistry directory #{dir}"
                Dir.mkdir(dir) 
              end
            }
          end
          unless dbs.has_key?(prefix)
            log "creating db #{@bot.botclass}/registry/#{prefix}.db"
            dbs[prefix] = BDB::CIBtree.open("#{@bot.botclass}/registry/#{prefix}.db",
              nil, BDB::CREATE | BDB::EXCL,
              0600, "env" => env)
          end
          dbs[prefix][key] = v
        }
        old.close
        File.rename("#{@bot.botclass}/plugin_registry.db", "#{@bot.botclass}/plugin_registry.db.old")
        dbs.each {|k,v|
          log "closing db #{k}"
          v.close
        }
        env.close
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
    def initialize(bot, name)
      @bot = bot
      @name = name.downcase
      dirs = File.dirname("#{@bot.botclass}/registry/#{@name}").split("/")
      dirs.length.times { |i|
        dir = dirs[0,i+1].join("/")+"/"
        unless File.exist?(dir)
          debug "creating subregistry directory #{dir}"
          Dir.mkdir(dir) 
        end
      }
      @registry = DBTree.new bot, "registry/#{@name}"
      @default = nil
      # debug "initializing registry accessor with name #{@name}"
    end

    def flush
      @registry.flush
      @registry.sync
    end

    def close
      @registry.close
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
      begin
        Marshal.restore(val)
      rescue Exception => e
        warning "failed to restore marshal data for #{val.inspect}, falling back to default"
        debug e.inspect
        debug e.backtrace.join("\n")
        if @default != nil
          begin
            return Marshal.restore(@default)
          rescue
            return nil
          end
        else
          return nil
        end
      end
    end

    # lookup a key in the registry
    def [](key)
      if @registry.has_key?(key)
        return restore(@registry[key])
      elsif @default != nil
        return restore(@default)
      else
        return nil
      end
    end

    # set a key in the registry
    def []=(key,value)
      @registry[key] = store(value)
    end

    # set the default value for registry lookups, if the key sought is not
    # found, the default will be returned. The default default (har) is nil.
    def set_default (default)
      @default = store(default)
    end

    # just like Hash#each
    def each(&block)
      @registry.each {|key,value|
        block.call(key, restore(value))
      }
    end

    # just like Hash#each_key
    def each_key(&block)
      @registry.each {|key, value|
        block.call(key)
      }
    end

    # just like Hash#each_value
    def each_value(&block)
      @registry.each {|key, value|
        block.call(restore(value))
      }
    end

    # just like Hash#has_key?
    def has_key?(key)
      return @registry.has_key?(key)
    end
    alias include? has_key?
    alias member? has_key?

    # just like Hash#has_both?
    def has_both?(key, value)
      return @registry.has_both?(key, store(value))
    end

    # just like Hash#has_value?
    def has_value?(value)
      return @registry.has_value?(store(value))
    end

    # just like Hash#index?
    def index(value)
      ind = @registry.index(store(value))
      if ind
        return ind
      else
        return nil
      end
    end

    # delete a key from the registry
    def delete(key)
      return @registry.delete(key)
    end

    # returns a list of your keys
    def keys
      return @registry.keys
    end

    # Return an array of all associations [key, value] in your namespace
    def to_a
      ret = Array.new
      @registry.each {|key, value|
        ret << [key, restore(value)]
      }
      return ret
    end

    # Return an hash of all associations {key => value} in your namespace
    def to_hash
      ret = Hash.new
      @registry.each {|key, value|
        ret[key] = restore(value)
      }
      return ret
    end

    # empties the registry (restricted to your namespace)
    def clear
      @registry.clear
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

    def sub_registry(prefix)
      return BotRegistryAccessor.new(@bot, @name + "/" + prefix)
    end

    # returns the number of keys in your registry namespace
    def length
      self.keys.length
    end
    alias size length

  end

end
