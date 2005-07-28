module Irc
  require 'rbot/messagemapper'

  # base class for all rbot plugins
  # certain methods will be called if they are provided, if you define one of
  # the following methods, it will be called as appropriate:
  #
  # map(template, options)::
  #    map is the new, cleaner way to respond to specific message formats
  #    without littering your plugin code with regexps
  #    examples:
  #      plugin.map 'karmastats', :action => 'karma_stats'
  #
  #      # while in the plugin...
  #      def karma_stats(m, params)
  #        m.reply "..."
  #      end
  #      
  #      # the default action is the first component
  #      plugin.map 'karma'
  #
  #      # attributes can be pulled out of the match string
  #      plugin.map 'karma for :key'
  #      plugin.map 'karma :key'
  #
  #      # while in the plugin...
  #      def karma(m, params)
  #        item = params[:key]
  #        m.reply 'karma for #{item}'
  #      end
  #      
  #      # you can setup defaults, to make parameters optional
  #      plugin.map 'karma :key', :defaults => {:key => 'defaultvalue'}
  #      
  #      # the default auth check is also against the first component
  #      # but that can be changed
  #      plugin.map 'karmastats', :auth => 'karma'
  #
  #      # maps can be restricted to public or private message:
  #      plugin.map 'karmastats', :private false,
  #      plugin.map 'karmastats', :public false,
  #    end
  #
  #    To activate your maps, you simply register them
  #    plugin.register_maps
  #    This also sets the privmsg handler to use the map lookups for
  #    handling messages. You can still use listen(), kick() etc methods
  # 
  # listen(UserMessage)::
  #                        Called for all messages of any type. To
  #                        differentiate them, use message.kind_of? It'll be
  #                        either a PrivMessage, NoticeMessage, KickMessage,
  #                        QuitMessage, PartMessage, JoinMessage, NickMessage,
  #                        etc.
  #                              
  # privmsg(PrivMessage)::
  #                        called for a PRIVMSG if the first word matches one
  #                        the plugin register()d for. Use m.plugin to get
  #                        that word and m.params for the rest of the message,
  #                        if applicable.
  #
  # kick(KickMessage)::
  #                        Called when a user (or the bot) is kicked from a
  #                        channel the bot is in.
  #
  # join(JoinMessage)::
  #                        Called when a user (or the bot) joins a channel
  #
  # part(PartMessage)::
  #                        Called when a user (or the bot) parts a channel
  #
  # quit(QuitMessage)::    
  #                        Called when a user (or the bot) quits IRC
  #
  # nick(NickMessage)::
  #                        Called when a user (or the bot) changes Nick
  # topic(TopicMessage)::
  #                        Called when a user (or the bot) changes a channel
  #                        topic
  # 
  # save::                 Called when you are required to save your plugin's
  #                        state, if you maintain data between sessions
  #
  # cleanup::              called before your plugin is "unloaded", prior to a
  #                        plugin reload or bot quit - close any open
  #                        files/connections or flush caches here
  class Plugin
    attr_reader :bot   # the associated bot
    # initialise your plugin. Always call super if you override this method,
    # as important variables are set up for you
    def initialize
      @bot = Plugins.bot
      @names = Array.new
      @handler = MessageMapper.new(self)
      @registry = BotRegistryAccessor.new(@bot, self.class.to_s.gsub(/^.*::/, ""))
    end

    def map(*args)
      @handler.map(*args)
      # register this map
      name = @handler.last.items[0]
      self.register name
      unless self.respond_to?('privmsg')
        def self.privmsg(m)
          @handler.handle(m)
        end
      end
    end

    # return an identifier for this plugin, defaults to a list of the message
    # prefixes handled (used for error messages etc)
    def name
      @names.join("|")
    end
    
    # return a help string for your module. for complex modules, you may wish
    # to break your help into topics, and return a list of available topics if
    # +topic+ is nil. +plugin+ is passed containing the matching prefix for
    # this message - if your plugin handles multiple prefixes, make sure your
    # return the correct help for the prefix requested
    def help(plugin, topic)
      "no help"
    end
    
    # register the plugin as a handler for messages prefixed +name+
    # this can be called multiple times for a plugin to handle multiple
    # message prefixes
    def register(name)
      return if Plugins.plugins.has_key?(name)
      Plugins.plugins[name] = self
      @names << name
    end

    # default usage method provided as a utility for simple plugins. The
    # MessageMapper uses 'usage' as its default fallback method.
    def usage(m, params)
      m.reply "incorrect usage, ask for help using '#{@bot.nick}: help #{m.plugin}'"
    end

  end

  # class to manage multiple plugins and delegate messages to them for
  # handling
  class Plugins
    # hash of registered message prefixes and associated plugins
    @@plugins = Hash.new
    # associated IrcBot class
    @@bot = nil

    # bot::     associated IrcBot class
    # dirlist:: array of directories to scan (in order) for plugins
    #
    # create a new plugin handler, scanning for plugins in +dirlist+
    def initialize(bot, dirlist)
      @@bot = bot
      @dirs = dirlist
      scan
    end
    
    # access to associated bot
    def Plugins.bot
      @@bot
    end

    # access to list of plugins
    def Plugins.plugins
      @@plugins
    end

    # load plugins from pre-assigned list of directories
    def scan
      dirs = Array.new
      dirs << Config::DATADIR + "/plugins"
      dirs += @dirs
      dirs.each {|dir|
        if(FileTest.directory?(dir))
          d = Dir.new(dir)
          d.each {|file|
            next if(file =~ /^\./)
            next unless(file =~ /\.rb$/)
            @tmpfilename = "#{dir}/#{file}"

            # create a new, anonymous module to "house" the plugin
            plugin_module = Module.new
            
            begin
              plugin_string = IO.readlines(@tmpfilename).join("")
              debug "loading module: #{@tmpfilename}"
              plugin_module.module_eval(plugin_string)
            rescue StandardError, NameError, LoadError, SyntaxError => err
              puts "warning: plugin #{@tmpfilename} load failed: " + err
              puts err.backtrace.join("\n")
            end
          }
        end
      }
    end

    # call the save method for each active plugin
    def save
      @@plugins.values.uniq.each {|p|
        next unless(p.respond_to?("save"))
        begin
          p.save
        rescue StandardError, NameError, SyntaxError => err
          puts "plugin #{p.name} save() failed: " + err
          puts err.backtrace.join("\n")
        end
      }
    end

    # call the cleanup method for each active plugin
    def cleanup
      @@plugins.values.uniq.each {|p|
        next unless(p.respond_to?("cleanup"))
        begin
          p.cleanup
        rescue StandardError, NameError, SyntaxError => err
          puts "plugin #{p.name} cleanup() failed: " + err
          puts err.backtrace.join("\n")
        end
      }
    end

    # drop all plugins and rescan plugins on disk
    # calls save and cleanup for each plugin before dropping them
    def rescan
      save
      cleanup
      @@plugins = Hash.new
      scan
    end

    # return list of help topics (plugin names)
    def helptopics
      if(@@plugins.length > 0)
        # return " [plugins: " + @@plugins.keys.sort.join(", ") + "]"
        return " [#{length} plugins: " + @@plugins.values.uniq.collect{|p| p.name}.sort.join(", ") + "]"
      else
        return " [no plugins active]" 
      end
    end

    def length
      @@plugins.values.uniq.length
    end

    # return help for +topic+ (call associated plugin's help method)
    def help(topic="")
      if(topic =~ /^(\S+)\s*(.*)$/)
        key = $1
        params = $2
        if(@@plugins.has_key?(key))
          begin
            return @@plugins[key].help(key, params)
          rescue StandardError, NameError, SyntaxError => err
            puts "plugin #{@@plugins[key].name} help() failed: " + err
            puts err.backtrace.join("\n")
          end
        else
          return false
        end
      end
    end
    
    # see if each plugin handles +method+, and if so, call it, passing
    # +message+ as a parameter
    def delegate(method, message)
      @@plugins.values.uniq.each {|p|
        if(p.respond_to? method)
          begin
            p.send method, message
          rescue StandardError, NameError, SyntaxError => err
            puts "plugin #{p.name} #{method}() failed: " + err
            puts err.backtrace.join("\n")
          end
        end
      }
    end

    # see if we have a plugin that wants to handle this message, if so, pass
    # it to the plugin and return true, otherwise false
    def privmsg(m)
      return unless(m.plugin)
      if (@@plugins.has_key?(m.plugin) &&
          @@plugins[m.plugin].respond_to?("privmsg") &&
          @@bot.auth.allow?(m.plugin, m.source, m.replyto))
        begin
          @@plugins[m.plugin].privmsg(m)
        rescue StandardError, NameError, SyntaxError => err
          puts "plugin #{@@plugins[m.plugin].name} privmsg() failed: " + err
          puts err.backtrace.join("\n")
        end
        return true
      end
      return false
    end
  end

end
