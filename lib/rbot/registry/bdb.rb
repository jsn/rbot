#-- vim:sw=2:et
#++
#
# :title: Berkeley DB interface

begin
  require 'bdb'
rescue LoadError
  fatal "rbot couldn't load the bdb module, perhaps you need to install it? try http://www.ruby-lang.org/en/raa-list.rhtml?name=bdb or http://github.com/knu/ruby-bdb"
rescue Exception => e
  fatal "rbot couldn't load the bdb module: #{e.pretty_inspect}"
end

if not defined? BDB
  exit 2
end

module Irc
  DBFatal = BDB::Fatal
end

if BDB::VERSION_MAJOR < 4
  fatal "Your bdb (Berkeley DB) version #{BDB::VERSION} is too old!"
  fatal "rbot will only run with bdb version 4 or higher, please upgrade."
  fatal "For maximum reliability, upgrade to version 4.2 or higher."
  raise BDB::Fatal, BDB::VERSION + " is too old"
end

if BDB::VERSION_MAJOR == 4 and BDB::VERSION_MINOR < 2
  warning "Your bdb (Berkeley DB) version #{BDB::VERSION} may not be reliable."
  warning "If possible, try upgrade version 4.2 or later."
end

# make BTree lookups case insensitive
module BDB
  class CIBtree < Btree
    def bdb_bt_compare(a, b)
      if a == nil || b == nil
        warning "CIBTree: comparing key #{a.inspect} with #{b.inspect}"
      end
      (a||'').downcase <=> (b||'').downcase
    end
  end
end

module Irc

  # DBHash is for tying a hash to disk (using bdb).
  # Call it with an identifier, for example "mydata". It'll look for
  # mydata.db, if it exists, it will load and reference that db.
  # Otherwise it'll create and empty db called mydata.db
  class DBHash

    # absfilename:: use +key+ as an actual filename, don't prepend the bot's
    #               config path and don't append ".db"
    def initialize(bot, key, absfilename=false)
      @bot = bot
      @key = key
      relfilename = @bot.path key
      relfilename << '.db'
      if absfilename && File.exist?(key)
        # db already exists, use it
        @db = DBHash.open_db(key)
      elsif absfilename
        # create empty db
        @db = DBHash.create_db(key)
      elsif File.exist? relfilename
        # db already exists, use it
        @db = DBHash.open_db relfilename
      else
        # create empty db
        @db = DBHash.create_db relfilename
      end
    end

    def method_missing(method, *args, &block)
      return @db.send(method, *args, &block)
    end

    def DBHash.create_db(name)
      debug "DBHash: creating empty db #{name}"
      return BDB::Hash.open(name, nil,
      BDB::CREATE | BDB::EXCL, 0600)
    end

    def DBHash.open_db(name)
      debug "DBHash: opening existing db #{name}"
      return BDB::Hash.open(name, nil, "r+", 0600)
    end

  end


  # DBTree is a BTree equivalent of DBHash, with case insensitive lookups.
  class DBTree
    @@env=nil
    # TODO: make this customizable
    # Note that it must be at least four times lg_bsize
    @@lg_max = 8*1024*1024
    # absfilename:: use +key+ as an actual filename, don't prepend the bot's
    #               config path and don't append ".db"
    def initialize(bot, key, absfilename=false)
      @bot = bot
      @key = key
      if @@env.nil?
        begin
          @@env = BDB::Env.open(@bot.botclass, BDB::INIT_TRANSACTION | BDB::CREATE | BDB::RECOVER, "set_lg_max" => @@lg_max)
          debug "DBTree: environment opened with max log size #{@@env.conf['lg_max']}"
        rescue => e
          debug "DBTree: failed to open environment: #{e.pretty_inspect}. Retrying ..."
          @@env = BDB::Env.open(@bot.botclass, BDB::INIT_TRANSACTION | BDB::CREATE |  BDB::RECOVER)
        end
        #@@env = BDB::Env.open(@bot.botclass, BDB::CREATE | BDB::INIT_MPOOL | BDB::RECOVER)
      end

      relfilename = @bot.path key
      relfilename << '.db'

      if absfilename && File.exist?(key)
        # db already exists, use it
        @db = DBTree.open_db(key)
      elsif absfilename
        # create empty db
        @db = DBTree.create_db(key)
      elsif File.exist? relfilename
        # db already exists, use it
        @db = DBTree.open_db relfilename
      else
        # create empty db
        @db = DBTree.create_db relfilename
      end
    end

    def method_missing(method, *args, &block)
      return @db.send(method, *args, &block)
    end

    def DBTree.create_db(name)
      debug "DBTree: creating empty db #{name}"
      return @@env.open_db(BDB::CIBtree, name, nil, BDB::CREATE | BDB::EXCL, 0600)
    end

    def DBTree.open_db(name)
      debug "DBTree: opening existing db #{name}"
      return @@env.open_db(BDB::CIBtree, name, nil, "r+", 0600)
    end

    def DBTree.cleanup_logs()
      if @@env.nil?
        debug "No BDB environment, skipping checkpoint"
        return
      end
      begin
        debug "DBTree: checkpointing ..."
        @@env.checkpoint
      rescue Exception => e
        debug "Failed: #{e.pretty_inspect}"
      end
      begin
        debug "DBTree: flushing log ..."
        @@env.log_flush
        logs = @@env.log_archive(BDB::ARCH_ABS)
        debug "DBTree: deleting archivable logs: #{logs.join(', ')}."
        logs.each { |log|
          File.delete(log)
        }
      rescue Exception => e
        debug "Failed: #{e.pretty_inspect}"
      end
    end

    def DBTree.stats()
      if @@env.nil?
        debug "No BDB environment, no stats"
        return
      end
      begin
        debug "General stats:"
        debug @@env.stat
        debug "Lock stats:"
        debug @@env.lock_stat
        debug "Log stats:"
        debug @@env.log_stat
        debug "Txn stats:"
        debug @@env.txn_stat
      rescue
        debug "Couldn't dump stats"
      end
    end

    def DBTree.cleanup_env()
      if @@env.nil?
        debug "No BDB environment, skipping cleanup"
        return
      end
      begin
        debug "DBTree: checking transactions ..."
        has_active_txn = @@env.txn_stat["st_nactive"] > 0
        if has_active_txn
          warning "DBTree: not all transactions completed!"
        end
        DBTree.cleanup_logs
        debug "DBTree: closing environment #{@@env}"
        path = @@env.home
        @@env.close
        @@env = nil
        if has_active_txn
          debug "DBTree: keeping file because of incomplete transactions"
        else
          debug "DBTree: cleaning up environment in #{path}"
          BDB::Env.remove("#{path}")
        end
      rescue Exception => e
        error "failed to clean up environment: #{e.pretty_inspect}"
      end
    end

  end

end


module Irc
class Bot

  # This class is now used purely for upgrading from prior versions of rbot
  # the new registry is split into multiple DBHash objects, one per plugin
  class Registry
    def initialize(bot)
      @bot = bot
      upgrade_data
      upgrade_data2
    end

    # check for older versions of rbot with data formats that require updating
    # NB this function is called _early_ in init(), pretty much all you have to
    # work with is @bot.botclass.
    def upgrade_data
      oldreg = @bot.path 'registry.db'
      newreg = @bot.path 'plugin_registry.db'
      if File.exist?(oldreg)
        log _("upgrading old-style (rbot 0.9.5 or earlier) plugin registry to new format")
        old = BDB::Hash.open(oldreg, nil, "r+", 0600)
        new = BDB::CIBtree.open(newreg, nil, BDB::CREATE | BDB::EXCL, 0600)
        old.each {|k,v|
          new[k] = v
        }
        old.close
        new.close
        File.rename(oldreg, oldreg + ".old")
      end
    end

    def upgrade_data2
      oldreg = @bot.path 'plugin_registry.db'
      newdir = @bot.path 'registry'
      if File.exist?(oldreg)
        Dir.mkdir(newdir) unless File.exist?(newdir)
        env = BDB::Env.open(@bot.botclass, BDB::INIT_TRANSACTION | BDB::CREATE | BDB::RECOVER)# | BDB::TXN_NOSYNC)
        dbs = Hash.new
        log _("upgrading previous (rbot 0.9.9 or earlier) plugin registry to new split format")
        old = BDB::CIBtree.open(oldreg, nil, "r+", 0600, "env" => env)
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
                log _("creating subregistry directory #{dir}")
                Dir.mkdir(dir)
              end
            }
          end
          unless dbs.has_key?(prefix)
            log _("creating db #{@bot.botclass}/registry/#{prefix}.db")
            dbs[prefix] = BDB::CIBtree.open("#{@bot.botclass}/registry/#{prefix}.db",
              nil, BDB::CREATE | BDB::EXCL,
              0600, "env" => env)
          end
          dbs[prefix][key] = v
        }
        old.close
        File.rename(oldreg, oldreg + ".old")
        dbs.each {|k,v|
          log _("closing db #{k}")
          v.close
        }
        env.close
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
  # will NOT modify the object in the registry - remember that Registry#[]
  # returns a Marshal.restore'd object, the object you just modified in place
  # will disappear. You would need to:
  #   blah = @registry[:blah]
  #   blah[:foo] = "flump"
  #   @registry[:blah] = blah
  #
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
  class Accessor

    attr_accessor :recovery

    # plugins don't call this - a Registry::Accessor is created for them and
    # is accessible via @registry.
    def initialize(bot, name)
      @bot = bot
      @name = name.downcase
      @filename = @bot.path 'registry', @name
      dirs = File.dirname(@filename).split("/")
      dirs.length.times { |i|
        dir = dirs[0,i+1].join("/")+"/"
        unless File.exist?(dir)
          debug "creating subregistry directory #{dir}"
          Dir.mkdir(dir)
        end
      }
      @filename << ".db"
      @registry = nil
      @default = nil
      @recovery = nil
      # debug "initializing registry accessor with name #{@name}"
    end

    def registry
        @registry ||= DBTree.new @bot, "registry/#{@name}"
    end

    def flush
      # debug "fushing registry #{registry}"
      return if !@registry
      registry.flush
      registry.sync
    end

    def close
      # debug "closing registry #{registry}"
      return if !@registry
      registry.close
      @registry = nil
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
        error _("failed to restore marshal data for #{val.inspect}, attempting recovery or fallback to default")
        debug e
        if defined? @recovery and @recovery
          begin
            return @recovery.call(val)
          rescue Exception => ee
            error _("marshal recovery failed, trying default")
            debug ee
          end
        end
        return default
      end
    end

    # lookup a key in the registry
    def [](key)
      if File.exist?(@filename) && registry.has_key?(key)
        return restore(registry[key])
      else
        return default
      end
    end

    # set a key in the registry
    def []=(key,value)
      registry[key] = store(value)
    end

    # set the default value for registry lookups, if the key sought is not
    # found, the default will be returned. The default default (har) is nil.
    def set_default (default)
      @default = default
    end

    def default
      @default && (@default.dup rescue @default)
    end

    # just like Hash#each
    def each(set=nil, bulk=0, &block)
      return nil unless File.exist?(@filename)
      registry.each(set, bulk) {|key,value|
        block.call(key, restore(value))
      }
    end

    # just like Hash#each_key
    def each_key(set=nil, bulk=0, &block)
      return nil unless File.exist?(@filename)
      registry.each_key(set, bulk) {|key|
        block.call(key)
      }
    end

    # just like Hash#each_value
    def each_value(set=nil, bulk=0, &block)
      return nil unless File.exist?(@filename)
      registry.each_value(set, bulk) { |value|
        block.call(restore(value))
      }
    end

    # just like Hash#has_key?
    def has_key?(key)
      return false unless File.exist?(@filename)
      return registry.has_key?(key)
    end
    alias include? has_key?
    alias member? has_key?
    alias key? has_key?

    # just like Hash#has_both?
    def has_both?(key, value)
      return false unless File.exist?(@filename)
      return registry.has_both?(key, store(value))
    end

    # just like Hash#has_value?
    def has_value?(value)
      return false unless File.exist?(@filename)
      return registry.has_value?(store(value))
    end

    # just like Hash#index?
    def index(value)
      return nil unless File.exist?(@filename)
      ind = registry.index(store(value))
      if ind
        return ind
      else
        return nil
      end
    end

    # delete a key from the registry
    def delete(key)
      return default unless File.exist?(@filename)
      return registry.delete(key)
    end

    # returns a list of your keys
    def keys
      return [] unless File.exist?(@filename)
      return registry.keys
    end

    # Return an array of all associations [key, value] in your namespace
    def to_a
      return [] unless File.exist?(@filename)
      ret = Array.new
      registry.each {|key, value|
        ret << [key, restore(value)]
      }
      return ret
    end

    # Return an hash of all associations {key => value} in your namespace
    def to_hash
      return {} unless File.exist?(@filename)
      ret = Hash.new
      registry.each {|key, value|
        ret[key] = restore(value)
      }
      return ret
    end

    # empties the registry (restricted to your namespace)
    def clear
      return true unless File.exist?(@filename)
      registry.clear
    end
    alias truncate clear

    # returns an array of the values in your namespace of the registry
    def values
      return [] unless File.exist?(@filename)
      ret = Array.new
      self.each {|k,v|
        ret << restore(v)
      }
      return ret
    end

    def sub_registry(prefix)
      return Accessor.new(@bot, @name + "/" + prefix.to_s)
    end

    # returns the number of keys in your registry namespace
    def length
      self.keys.length
    end
    alias size length

  end

  end
end
end
