#-- vim:sw=2:et
#++
#
# :title: Remote service provider for rbot
#
# Author:: Giuseppe Bilotta (giuseppe.bilotta@gmail.com)
# Copyright:: Copyright (c) 2006 Giuseppe Bilotta
# License:: GPLv2
#
# From an idea by halorgium <rbot@spork.in>.
#
# TODO find a way to manage session id (logging out, manually and/or
# automatically)

require 'drb/drb'

module ::Irc

  module Auth

    # We extend the BotUser class to handle remote logins
    #
    class BotUser

      # A rather simple method to handle remote logins. Nothing special, just a
      # password check.
      #
      def remote_login(password)
        if password == @password
          debug "remote login for #{self.inspect} succeeded"
          return true
        else
          return false
        end
      end
    end

    # We extend the AuthManagerClass to handle remote logins
    #
    class AuthManagerClass

      MAX_SESSION_ID = 2**128 - 1

      # Creates a session id when the given password matches the given
      # botusername
      #
      def remote_login(botusername, pwd)
        @remote_users = Hash.new unless defined? @remote_users
        n = BotUser.sanitize_username(botusername)
        k = n.to_sym
        raise "No such BotUser #{n}" unless include?(k)
        bu = @allbotusers[k]
        if bu.remote_login(pwd)
          raise "ran out of session ids!" if @remote_users.length == MAX_SESSION_ID
          session_id = rand(MAX_SESSION_ID)
          while @remote_users.has_key?(session_id)
            session_id = rand(MAX_SESSION_ID)
          end
          @remote_users[session_id] = bu
          return session_id
        end
        return false
      end

      # Returns the botuser associated with the given session id
      def remote_user(session_id)
        return everyone unless session_id
        return nil unless defined? @remote_users
        if @remote_users.has_key?(session_id)
          return @remote_users[session_id]
        else
          return nil
        end
      end
    end

  end


  # A RemoteMessage is similar to a BasicUserMessage
  #
  class RemoteMessage
    # associated bot
    attr_reader :bot

    # when the message was received
    attr_reader :time

    # remote client that originated the message
    attr_reader :source

    # contents of the message
    attr_accessor :message

    def initialize(bot, source, message)
      @bot = bot
      @source = source
      @message = message
      @time = Time.now
    end

    # The target of a RemoteMessage
    def target
      @bot
    end

    # Remote messages are always 'private'
    def private?
      true
    end
  end

  # The RemoteDispatcher is a kind of MessageMapper, tuned to handle
  # RemoteMessages
  #
  class RemoteDispatcher < MessageMapper

    # It is initialized by passing it the bot instance
    #
    def initialize(bot)
      super
    end

    # The map method for the RemoteDispatcher returns the index of the inserted
    # template
    #
    def map(botmodule, *args)
      super
      return @templates.length - 1
    end

    # The unmap method for the RemoteDispatcher nils the template at the given index,
    # therefore effectively removing the mapping
    #
    def unmap(botmodule, handle)
      tmpl = @templates[handle]
      raise "Botmodule #{botmodule.name} tried to unmap #{tmpl.inspect} that was handled by #{tmpl.botmodule}" unless tmpl.botmodule == botmodule.name
      debug "Unmapping #{tmpl.inspect}"
      @templates[handle] = nil
      @templates.clear unless @templates.nitems > 0
    end

    # We redefine the handle() method from MessageMapper, taking into account
    # that @parent is a bot, and that we don't handle fallbacks.
    #
    # On failure to dispatch anything, the method returns false. If dispatching
    # is successfull, the method returns a Hash.
    #
    # Presently, the hash returned on success has only one key, :return, whose
    # value is the actual return value of the successfull dispatch.
    # 
    # TODO this same kind of mechanism could actually be used in MessageMapper
    # itself to be able to handle the case of multiple plugins having the same
    # 'first word' ...
    #
    #
    def handle(m)
      return false if @templates.empty?
      failures = []
      @templates.each do |tmpl|
        # Skip this element if it was unmapped
        next unless tmpl
        botmodule = @parent.plugins[tmpl.botmodule]
        options, failure = tmpl.recognize(m)
        if options.nil?
          failures << [tmpl, failure]
        else
          action = tmpl.options[:action]
          unless botmodule.respond_to?(action)
            failures << [tmpl, "#{botmodule} does not respond to action #{action}"]
            next
          end
          auth = tmpl.options[:full_auth_path]
          debug "checking auth for #{auth}"
          # We check for private permission
          if m.bot.auth.allow?(auth, m.source, '?')
            debug "template match found and auth'd: #{action.inspect} #{options.inspect}"
            return :return => botmodule.send(action, m, options)
          end
          debug "auth failed for #{auth}"
          # if it's just an auth failure but otherwise the match is good,
          # don't try any more handlers
          return false
        end
      end
      failures.each {|f, r|
        debug "#{f.inspect} => #{r}"
      }
      debug "no handler found"
      return false
    end

  end

  class Bot

    # The Irc::Bot::RemoteObject class represents and object that will take care
    # of interfacing with remote clients
    #
    # Example client session:
    #
    #   require 'drb'
    #   rbot = DRbObject.new_with_uri('druby://localhost:7268')
    #   id = rbot.delegate(nil, 'remote login someuser somepass')[:return]
    #   rbot.delegate(id, 'some secret command')
    #
    # Of course, the remote login is only neede for commands which may not be available
    # to everyone
    #
    class RemoteObject

      # We don't want this object to be copied clientside, so we make it undumpable
      include DRbUndumped

      # Initialization is simple
      def initialize(bot)
        @bot = bot
      end

      # The delegate method. This is the main method used by remote clients to send
      # commands to the bot. Most of the time, the method will be called with only
      # two parameters (session id and a String), but we allow more parameters
      # for future expansions.
      #
      # The session_id can be nil, meaning that the remote client wants to work as
      # an anoynomus botuser.
      #
      def delegate(session_id, *pars)
        warn "Ignoring extra parameters" if pars.length > 1
        cmd = pars.first
        client = @bot.auth.remote_user(session_id)
        raise "No such session id #{session_id}" unless client
        debug "Trying to dispatch command #{cmd.inspect} from #{client.inspect} authorized by #{session_id.inspect}"
        m = RemoteMessage.new(@bot, client, cmd)
        @bot.remote_dispatcher.handle(m)
      end

      private :instance_variables, :instance_variable_get, :instance_variable_set
    end

    # The bot also manages a single (for the moment) remote dispatcher. This method
    # makes it accessible to the outside world, creating it if necessary.
    #
    def remote_dispatcher
      if defined? @remote_dispatcher
        @remote_dispatcher
      else
        @remote_dispatcher = RemoteDispatcher.new(self)
      end
    end

    # The bot also manages a single (for the moment) remote object. This method
    # makes it accessible to the outside world, creating it if necessary.
    #
    def remote_object
      if defined? @remote_object
        @remote_object
      else
        @remote_object = RemoteObject.new(self)
      end
    end

  end

  module Plugins

    # We create a new Ruby module that can be included by BotModules that want to
    # provide remote interfaces
    #
    module RemoteBotModule

      # The remote_map acts just like the BotModule#map method, except that
      # the map is registered to the @bot's remote_dispatcher. Also, the remote map handle
      # is handled for the cleanup management
      #
      def remote_map(*args)
        @remote_maps = Array.new unless defined? @remote_maps
        @remote_maps << @bot.remote_dispatcher.map(self, *args)
      end

      # Unregister the remote maps.
      #
      def remote_cleanup
        return unless defined? @remote_maps
        @remote_maps.each { |h|
          @bot.remote_dispatcher.unmap(self, h)
        }
        @remote_maps.clear
      end

      # Redefine the default cleanup method.
      #
      def cleanup
        super
        remote_cleanup
      end
    end

    # And just because I like consistency:
    #
    module RemoteCoreBotModule
      include RemoteBotModule
    end

    module RemotePlugin
      include RemoteBotModule
    end

  end

end

class RemoteModule < CoreBotModule

  include RemoteCoreBotModule

  BotConfig.register BotConfigBooleanValue.new('remote.autostart',
    :default => true,
    :requires_rescan => true,
    :desc => "Whether the remote service provider should be started automatically")

  BotConfig.register BotConfigIntegerValue.new('remote.port',
    :default => 7268, # that's 'rbot'
    :requires_rescan => true,
    :desc => "Port on which the remote interface will be presented")

  BotConfig.register BotConfigStringValue.new('remote.host',
    :default => '',
    :requires_rescan => true,
    :desc => "Port on which the remote interface will be presented")

  def initialize
    super
    @port = @bot.config['remote.port']
    @host = @bot.config['remote.host']
    @drb = nil
    begin
      start_service if @bot.config['remote.autostart']
    rescue => e
      error "couldn't start remote service provider: #{e.inspect}"
    end
  end

  def start_service
    raise "Remote service provider already running" if @drb
    @drb = DRb.start_service("druby://#{@host}:#{@port}", @bot.remote_object)
  end

  def stop_service
    @drb.stop_service if @drb
    @drb = nil
  end

  def cleanup
    stop_service
    super
  end

  def handle_start(m, params)
    if @drb
      rep = "remote service provider already running"
      rep << " on port #{@port}" if m.private?
    else
      begin
        start_service(@port)
        rep = "remote service provider started"
        rep << " on port #{@port}" if m.private?
      rescue
        rep = "couldn't start remote service provider"
      end
    end
    m.reply rep
  end

  def remote_test(m, params)
    @bot.say params[:channel], "This is a remote test"
  end

  def remote_login(m, params)
    id = @bot.auth.remote_login(params[:botuser], params[:password])
    raise "login failed" unless id
    return id
  end

end

remote = RemoteModule.new

remote.map "remote start",
  :action => 'handle_start',
  :auth_path => ':manage:'

remote.map "remote stop",
  :action => 'handle_stop',
  :auth_path => ':manage:'

remote.default_auth('*', false)

remote.remote_map "remote test :channel",
  :action => 'remote_test'

remote.remote_map "remote login :botuser :password",
  :action => 'remote_login'

remote.default_auth('login', true)
