require 'singleton'

module Irc
    BotConfig.register BotConfigArrayValue.new('plugins.blacklist',
      :default => [], :wizard => false, :requires_restart => true,
      :desc => "Plugins that should not be loaded")
module Plugins
  require 'rbot/messagemapper'

=begin
  base class for all rbot plugins
  certain methods will be called if they are provided, if you define one of
  the following methods, it will be called as appropriate:

  map(template, options)::
  map!(template, options)::
     map is the new, cleaner way to respond to specific message formats
     without littering your plugin code with regexps. The difference
     between map and map! is that map! will not register the new command
     as an alternative name for the plugin.

     Examples:

       plugin.map 'karmastats', :action => 'karma_stats'

       # while in the plugin...
       def karma_stats(m, params)
         m.reply "..."
       end

       # the default action is the first component
       plugin.map 'karma'

       # attributes can be pulled out of the match string
       plugin.map 'karma for :key'
       plugin.map 'karma :key'

       # while in the plugin...
       def karma(m, params)
         item = params[:key]
         m.reply 'karma for #{item}'
       end

       # you can setup defaults, to make parameters optional
       plugin.map 'karma :key', :defaults => {:key => 'defaultvalue'}

       # the default auth check is also against the first component
       # but that can be changed
       plugin.map 'karmastats', :auth => 'karma'

       # maps can be restricted to public or private message:
       plugin.map 'karmastats', :private false,
       plugin.map 'karmastats', :public false,
     end

  listen(UserMessage)::
                         Called for all messages of any type. To
                         differentiate them, use message.kind_of? It'll be
                         either a PrivMessage, NoticeMessage, KickMessage,
                         QuitMessage, PartMessage, JoinMessage, NickMessage,
                         etc.

  privmsg(PrivMessage)::
                         called for a PRIVMSG if the first word matches one
                         the plugin register()d for. Use m.plugin to get
                         that word and m.params for the rest of the message,
                         if applicable.

  kick(KickMessage)::
                         Called when a user (or the bot) is kicked from a
                         channel the bot is in.

  join(JoinMessage)::
                         Called when a user (or the bot) joins a channel

  part(PartMessage)::
                         Called when a user (or the bot) parts a channel

  quit(QuitMessage)::
                         Called when a user (or the bot) quits IRC

  nick(NickMessage)::
                         Called when a user (or the bot) changes Nick
  topic(TopicMessage)::
                         Called when a user (or the bot) changes a channel
                         topic

  connect()::            Called when a server is joined successfully, but
                         before autojoin channels are joined (no params)

  save::                 Called when you are required to save your plugin's
                         state, if you maintain data between sessions

  cleanup::              called before your plugin is "unloaded", prior to a
                         plugin reload or bot quit - close any open
                         files/connections or flush caches here
=end

  class BotModule
    attr_reader :bot   # the associated bot
    # initialise your bot module. Always call super if you override this method,
    # as important variables are set up for you
    def initialize
      @bot = Plugins.pluginmanager.bot
      @botmodule_triggers = Array.new
      @handler = MessageMapper.new(self)
      @registry = BotRegistryAccessor.new(@bot, self.class.to_s.gsub(/^.*::/, ""))
    end

    def flush_registry
      # debug "Flushing #{@registry}"
      @registry.flush
    end

    def cleanup
      # debug "Closing #{@registry}"
      @registry.close
    end

    def handle(m)
      @handler.handle(m)
    end

    def map(*args)
      @handler.map(*args)
      # register this map
      name = @handler.last.items[0]
      self.register name
      unless self.respond_to?('privmsg')
        def self.privmsg(m)
          handle(m)
        end
      end
    end

    def map!(*args)
      @handler.map(*args)
      # register this map
      name = @handler.last.items[0]
      self.register name, {:hidden => true}
      unless self.respond_to?('privmsg')
        def self.privmsg(m)
          handle(m)
        end
      end
    end

    # return an identifier for this plugin, defaults to a list of the message
    # prefixes handled (used for error messages etc)
    def name
      self.class.downcase.sub(/(plugin)?$/,"")
    end

    # return a help string for your module. for complex modules, you may wish
    # to break your help into topics, and return a list of available topics if
    # +topic+ is nil. +plugin+ is passed containing the matching prefix for
    # this message - if your plugin handles multiple prefixes, make sure you
    # return the correct help for the prefix requested
    def help(plugin, topic)
      "no help"
    end

    # register the plugin as a handler for messages prefixed +name+
    # this can be called multiple times for a plugin to handle multiple
    # message prefixes
    def register(name, kl, opts={})
      raise ArgumentError, "Third argument must be a hash!" unless opts.kind_of?(Hash)
      return if Plugins.pluginmanager.botmodules[kl].has_key?(name)
      Plugins.pluginmanager.botmodules[kl][name] = self
      @botmodule_triggers << name unless opts.fetch(:hidden, false)
    end

    # default usage method provided as a utility for simple plugins. The
    # MessageMapper uses 'usage' as its default fallback method.
    def usage(m, params = {})
      m.reply "incorrect usage, ask for help using '#{@bot.nick}: help #{m.plugin}'"
    end

  end

  class CoreBotModule < BotModule
    def register(name, opts={})
      raise ArgumentError, "Second argument must be a hash!" unless opts.kind_of?(Hash)
      super(name, :core, opts)
    end
  end

  class Plugin < BotModule
    def register(name, opts={})
      raise ArgumentError, "Second argument must be a hash!" unless opts.kind_of?(Hash)
      super(name, :plugin, opts)
    end
  end

  # class to manage multiple plugins and delegate messages to them for
  # handling
  class PluginManagerClass
    include Singleton
    attr_reader :bot
    attr_reader :botmodules

    def initialize
      bot_associate(nil)
    end

    # Associate with bot _bot_
    def bot_associate(bot)
      @botmodules = {
        :core => Hash.new,
        :plugin => Hash.new
      }

      # associated IrcBot class
      @bot = bot
    end

    # Returns a hash of the registered message prefixes and associated
    # plugins
    def plugins
      @botmodules[:plugin]
    end

    # Returns a hash of the registered message prefixes and associated
    # core modules
    def core_modules
      @botmodules[:core]
    end

    # Makes a string of error _err_ by adding text _str_
    def report_error(str, err)
      ([str, err.inspect] + err.backtrace).join("\n")
    end

    # This method is the one that actually loads a module from the
    # file _fname_
    #
    # _desc_ is a simple description of what we are loading (plugin/botmodule/whatever)
    #
    # It returns the Symbol :loaded on success, and an Exception
    # on failure
    #
    def load_botmodule_file(fname, desc=nil)
      # create a new, anonymous module to "house" the plugin
      # the idea here is to prevent namespace pollution. perhaps there
      # is another way?
      plugin_module = Module.new

      desc = desc.to_s + " " if desc
      begin
        plugin_string = IO.readlines(fname).join("")
        debug "loading #{desc}#{fname}"
        plugin_module.module_eval(plugin_string, fname)
        return :loaded
      rescue Exception => err
        # rescue TimeoutError, StandardError, NameError, LoadError, SyntaxError => err
        warning report_error("#{desc}#{fname} load failed", err)
        bt = err.backtrace.select { |line|
          line.match(/^(\(eval\)|#{fname}):\d+/)
        }
        bt.map! { |el|
          el.gsub(/^\(eval\)(:\d+)(:in `.*')?(:.*)?/) { |m|
            "#{fname}#{$1}#{$3}"
          }
        }
        msg = err.to_str.gsub(/^\(eval\)(:\d+)(:in `.*')?(:.*)?/) { |m|
          "#{fname}#{$1}#{$3}"
        }
        newerr = err.class.new(msg)
        newerr.set_backtrace(bt)
        return newerr
      end
    end
    private :load_botmodule_file

    # Load core botmodules
    def load_core(dir)
      # TODO FIXME should this be hardcoded?
      if(FileTest.directory?(dir))
        d = Dir.new(dir)
        d.sort.each { |file|
          next unless(file =~ /[^.]\.rb$/)

          did_it = load_botmodule_file("#{dir}/#{file}", "core module")
          case did_it
          when Symbol
            # debug "loaded core botmodule #{dir}/#{file}"
          when Exception
            raise "failed to load core botmodule #{dir}/#{file}!"
          end
        }
      end
    end

    # dirlist:: array of directories to scan (in order) for plugins
    #
    # create a new plugin handler, scanning for plugins in +dirlist+
    def load_plugins(dirlist)
      @dirs = dirlist
      scan
    end

    # load plugins from pre-assigned list of directories
    def scan
      @failed = Array.new
      @ignored = Array.new
      processed = Hash.new

      @bot.config['plugins.blacklist'].each { |p|
        pn = p + ".rb"
        processed[pn.intern] = :blacklisted
      }

      dirs = Array.new
      # TODO FIXME should this be hardcoded?
      dirs << Config::datadir + "/plugins"
      dirs += @dirs
      dirs.reverse.each {|dir|
        if(FileTest.directory?(dir))
          d = Dir.new(dir)
          d.sort.each {|file|

            next if(file =~ /^\./)

            if processed.has_key?(file.intern)
              @ignored << {:name => file, :dir => dir, :reason => processed[file.intern]}
              next
            end

            if(file =~ /^(.+\.rb)\.disabled$/)
              # GB: Do we want to do this? This means that a disabled plugin in a directory
              #     will disable in all subsequent directories. This was probably meant
              #     to be used before plugins.blacklist was implemented, so I think
              #     we don't need this anymore
              processed[$1.intern] = :disabled
              @ignored << {:name => $1, :dir => dir, :reason => processed[$1.intern]}
              next
            end

            next unless(file =~ /\.rb$/)

            did_it = load_botmodule_file("#{dir}/#{file}", "plugin")
            case did_it
            when Symbol
              processed[file.intern] = did_it
            when Exception
              @failed <<  { :name => file, :dir => dir, :reason => did_it }
            end

          }
        end
      }
    end

    # call the save method for each active plugin
    def save
      delegate 'flush_registry'
      delegate 'save'
    end

    # call the cleanup method for each active plugin
    def cleanup
      delegate 'cleanup'
    end

    # drop all plugins and rescan plugins on disk
    # calls save and cleanup for each plugin before dropping them
    def rescan
      save
      cleanup
      plugins.clear
      scan
    end

    def status(short=false)
      # Active plugins first
      if(self.length > 0)
        list = "#{self.length} plugin#{'s' if length > 1}"
        if short
          list << " loaded"
        else
          list << ": " + @@plugins.values.uniq.collect{|p| p.name}.sort.join(", ")
        end
      else
        list = "no plugins active"
      end
      # Ignored plugins next
      unless @ignored.empty?
        list << "; #{Underline}#{@ignored.length} plugin#{'s' if @ignored.length > 1} ignored#{Underline}"
        list << ": use #{Bold}help ignored plugins#{Bold} to see why" unless short
      end
      # Failed plugins next
      unless @failed.empty?
        list << "; #{Reverse}#{@failed.length} plugin#{'s' if @failed.length > 1} failed to load#{Reverse}"
        list << ": use #{Bold}help failed plugins#{Bold} to see why" unless short
      end
      list
    end

    # return list of help topics (plugin names)
    def helptopics
      return " [#{status}]"
    end

    def length
      plugins.values.uniq.length
    end

    # return help for +topic+ (call associated plugin's help method)
    def help(topic="")
      case topic
      when /fail(?:ed)?\s*plugins?.*(trace(?:back)?s?)?/
        # debug "Failures: #{@failed.inspect}"
        return "no plugins failed to load" if @failed.empty?
        return (@failed.inject(Array.new) { |list, p|
          list << "#{Bold}#{p[:name]}#{Bold} in #{p[:dir]} failed"
          list << "with error #{p[:reason].class}: #{p[:reason]}"
          list << "at #{p[:reason].backtrace.join(', ')}" if $1 and not p[:reason].backtrace.empty?
          list
        }).join("\n")
      when /ignored?\s*plugins?/
        return "no plugins were ignored" if @ignored.empty?
        return (@ignored.inject(Array.new) { |list, p|
          case p[:reason]
          when :loaded
            list << "#{p[:name]} in #{p[:dir]} (overruled by previous)"
          else
            list << "#{p[:name]} in #{p[:dir]} (#{p[:reason].to_s})"
          end
          list
        }).join(", ")
      when /^(\S+)\s*(.*)$/
        key = $1
        params = $2
        if(@@plugins.has_key?(key))
          begin
            return @@plugins[key].help(key, params)
          rescue Exception => err
            #rescue TimeoutError, StandardError, NameError, SyntaxError => err
            error report_error("plugin #{@@plugins[key].name} help() failed:", err)
          end
        else
          return false
        end
      end
    end

    # see if each plugin handles +method+, and if so, call it, passing
    # +message+ as a parameter
    def delegate(method, *args)
      [core_modules, plugins].each { |pl|
        pl.values.uniq.each {|p|
          if(p.respond_to? method)
            begin
              p.send method, *args
            rescue Exception => err
              #rescue TimeoutError, StandardError, NameError, SyntaxError => err
              error report_error("plugin #{p.name} #{method}() failed:", err)
            end
          end
        }
      }
    end

    # see if we have a plugin that wants to handle this message, if so, pass
    # it to the plugin and return true, otherwise false
    def privmsg(m)
      [core_modules, plugins].each { |pl|
        return unless(m.plugin)
        if (pl.has_key?(m.plugin) &&
          pl[m.plugin].respond_to?("privmsg") &&
          @bot.auth.allow?(m.plugin, m.source, m.replyto))
          begin
            pl[m.plugin].privmsg(m)
          rescue BDB::Fatal => err
            error error_report("plugin #{pl[m.plugin].name} privmsg() failed:", err)
            raise
          rescue Exception => err
            #rescue TimeoutError, StandardError, NameError, SyntaxError => err
            error "plugin #{pl[m.plugin].name} privmsg() failed: #{err.class}: #{err}\n#{error err.backtrace.join("\n")}"
          end
          return true
        end
        return false
      }
    end
  end

  # Returns the only PluginManagerClass instance
  def Plugins.pluginmanager
    return PluginManagerClass.instance
  end

end
end
