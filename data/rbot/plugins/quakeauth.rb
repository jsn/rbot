#-- vim:sw=2:et
#++
#
# :title: QuakeNet Auth Plugin
#
# Author:: Raine Virta <rane@kapsi.fi>
# Copyright:: (C) 2008 Raine Virta
# License:: GPL v2
#
# Automatically auths with Q on QuakeNet servers

class QPlugin < Plugin

  def help(plugin, topic="")
    case topic
    when ""
      return "qauth plugin: handles Q auths. topics set, identify, register"
    when "set"
      return "qauth set <user> <password>: set the Q user and password and use it to identify in future"
    when "identify"
      return "qauth identify: identify with Q (if user and auth are set)"
    when "register"
      return "qauth register <email>: register with Q, an email on how to proceed will be sent to the email address you provide"
    end
  end

  def initialize
    super
    # this plugin only wants to store strings!
    class << @registry
      def store(val)
        val
      end
      def restore(val)
        val
      end
    end
    @source = nil
  end

  def set(m, params)
    @registry['quakenet.user'] = params[:nick]
    @registry['quakenet.auth'] = params[:password]
    m.okay
  end

  def connect
    identify(nil, {}) if on_quakenet?
  end

  def identify(m, params)
    @source = m.replyto if m
    @registry['quakenet.auth'] = params[:password] if params[:password]

    if @registry.has_key?('quakenet.user') && @registry.has_key?('quakenet.auth')
      user = @registry['quakenet.user']
      pass = @registry['quakenet.auth']

      debug "authing with Q using #{user} #{pass}"
      msg_q "auth #{user} #{pass}"
    else
      m.reply "not configured, try 'qauth set :nick :password' or 'qauth register :email'" if m
    end
  end

  def notice(m)
    if m.source.user == "TheQBot" && m.source.host = "CServe.quakenet.org"
      case m.message
      when /a user with that name already exists/i
        @bot.say @source, "user with my name already exists, identify if it belongs to you"
      when /created successfully/
        @registry['quakenet.user'] = @bot.nick
        @bot.say @source, "an email on how to proceed should have been sent to #{@email} -- 'qauth identify <password>' next"
      when /too many accounts exist from this email address/i
        @bot.say @source, "too many accounts on that email address"
      when /registration service is unavailable/
        @bot.say @source, "the registration service is unavailable, try again later"
      when /password incorrect/
        @bot.say @source, "username or password incorrect" if @source
      when /you are now logged in/i
        @bot.say @source, "authed successfully" if @source
        @bot.plugins.delegate('identified')
      when /auth is not available/
        @bot.say @source, "already authed" if @source
      end
    end
  end

  def register_nick(m, params)
    # check nick for invalid characters
    if @bot.nick =~ /[`~\^\[\]{}|_\\]/
      m.reply "for me to be able to register, my nick cannot have any of the following characters: `~^[]{}|_\\"
      return
    end

    @email  = params[:email]
    @source = m.replyto

    msg_q "hello #{@email} #{@email}"
  end

  def msg_q(message)
    @bot.say "Q@CServe.quakenet.org", message if on_quakenet?
  end

  def on_quakenet?
    @bot.server.hostname.split(".")[-2] == "quakenet"
  end
end

plugin = QPlugin.new
plugin.map 'qauth set :nick :password', :action => "set"
plugin.map 'qauth identify [:password]', :action => "identify"
plugin.map 'qauth register :email', :action => "register_nick"

plugin.default_auth('*', false)
