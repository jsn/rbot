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
# TODO client ID and auth
#

require 'drb/drb'

module ::Irc

  # A RemoteCommand is similar to a BaiscUserMessage
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

  class RemoteDispatcher < MessageMapper

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

    # The map method for the RemoteDispatcher returns the index of the inserted
    # template
    #
    def unmap(botmodule, handle)
      tmpl = @templates[handle]
      raise "Botmodule #{botmodule.name} tried to unmap #{tmpl.inspect} that was handled by #{tmpl.botmodule}" unless tmpl.botmodule == botmodule.name
      debug "Unmapping #{tmpl.inspect}"
      @templates[handle] = nil
      @templates.clear unless @templates.nitems > 0
    end

    # We redefine the handle() method from MessageMapper, taking into account
    # that @parent is a bot, and that we don't handle fallbacks
    #
    # TODO this same kind of mechanism could actually be used in MessageMapper
    # itself to be able to handle the case of multiple plugins having the same
    # 'first word' ...
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
          # TODO
          # auth = tmpl.options[:full_auth_path]
          # debug "checking auth for #{auth}"
          # if m.bot.auth.allow?(auth, m.source, m.replyto)
            debug "template match found and auth'd: #{action.inspect} #{options.inspect}"
            botmodule.send(action, m, options)
            return true
          # end
          # debug "auth failed for #{auth}"
          # # if it's just an auth failure but otherwise the match is good,
          # # don't try any more handlers
          # return false
        end
      end
      failures.each {|f, r|
        debug "#{f.inspect} => #{r}"
      }
      debug "no handler found"
      return false
    end

  end

  class IrcBot

    # The Irc::IrcBot::RemoteObject class represents and object that will take care
    # of interfacing with remote clients
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
      # two parameters (authorization code and a String), but we allow more parameters
      # for future expansions
      #
      def delegate(auth, *pars)
        warn "Ignoring extra parameters" if pars.length > 1
        cmd = pars.first
        # TODO implement auth <-> client conversion
        # We need at least a RemoteBotUser class derived from Irc::Auth::BotUser
        # and a way to associate the auth info to the appropriate RemoteBotUser class
        client = auth
        debug "Trying to dispatch command #{cmd.inspect} authorized by #{auth.inspect}"
        m = RemoteMessage.new(@bot, client, cmd)
        @bot.remote_dispatcher.handle(m)
      end
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

end

remote = RemoteModule.new

remote.map "remote start",
  :action => 'handle_start',
  :auth_path => ':manage:'

remote.map "remote stop",
  :action => 'handle_stop',
  :auth_path => ':manage:'

remote.remote_map "remote test :channel",
  :action => 'remote_test'

remote.default_auth('*', false)
