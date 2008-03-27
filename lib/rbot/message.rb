#-- vim:sw=2:et
#++
#
# :title: IRC message datastructures

module Irc


  class Bot
    module Config
      Config.register ArrayValue.new('core.address_prefix',
        :default => [], :wizard => true,
        :desc => "what non nick-matching prefixes should the bot respond to as if addressed (e.g !, so that '!foo' is treated like 'rbot: foo')"
      )

      Config.register BooleanValue.new('core.reply_with_nick',
        :default => false, :wizard => true,
        :desc => "if true, the bot will prepend the nick to what he has to say when replying (e.g. 'markey: you can't do that!')"
      )

      Config.register StringValue.new('core.nick_postfix',
        :default => ':', :wizard => true,
        :desc => "when replying with nick put this character after the nick of the user the bot is replying to"
      )
    end
  end


  # Define standard IRC attriubtes (not so standard actually,
  # but the closest thing we have ...)
  Bold = "\002"
  Underline = "\037"
  Reverse = "\026"
  Italic = "\011"
  NormalText = "\017"

  # Color is prefixed by \003 and followed by optional
  # foreground and background specifications, two-digits-max
  # numbers separated by a comma. One of the two parts
  # must be present.
  Color = "\003"
  ColorRx = /#{Color}\d?\d?(?:,\d\d?)?/

  # Standard color codes
  ColorCode = {
    :black      => 1,
    :blue       => 2,
    :navyblue   => 2,
    :navy_blue  => 2,
    :green      => 3,
    :red        => 4,
    :brown      => 5,
    :purple     => 6,
    :olive      => 7,
    :yellow     => 8,
    :limegreen  => 9,
    :lime_green => 9,
    :teal       => 10,
    :aqualight  => 11,
    :aqua_light => 11,
    :royal_blue => 12,
    :hotpink    => 13,
    :hot_pink   => 13,
    :darkgray   => 14,
    :dark_gray  => 14,
    :lightgray  => 15,
    :light_gray => 15,
    :white      => 16
  }

  # Convert a String or Symbol into a color number
  def Irc.find_color(data)
    if Integer === data
      data
    else
      f = if String === data
            data.intern
          else
            data
          end
      if ColorCode.key?(f)
        ColorCode[f] 
      else
        0
      end
    end
  end

  # Insert the full color code for a given
  # foreground/background combination.
  def Irc.color(fg=nil,bg=nil)
    str = Color.dup
    if fg
     str << Irc.find_color(fg).to_s
    end
    if bg
      str << "," << Irc.find_color(bg).to_s
    end
    return str
  end

  # base user message class, all user messages derive from this
  # (a user message is defined as having a source hostmask, a target
  # nick/channel and a message part)
  class BasicUserMessage

    # associated bot
    attr_reader :bot

    # associated server
    attr_reader :server

    # when the message was received
    attr_reader :time

    # User that originated the message
    attr_reader :source

    # User/Channel message was sent to
    attr_reader :target

    # contents of the message
    attr_accessor :message

    # contents of the message (for logging purposes)
    attr_accessor :logmessage

    # has the message been replied to/handled by a plugin?
    attr_accessor :replied

    # instantiate a new Message
    # bot::      associated bot class
    # server::   Server where the message took place
    # source::   User that sent the message
    # target::   User/Channel is destined for
    # message::  actual message
    def initialize(bot, server, source, target, message)
      @msg_wants_id = false unless defined? @msg_wants_id

      @time = Time.now
      @bot = bot
      @source = source
      @address = false
      @target = target
      @message = BasicUserMessage.stripcolour message
      @replied = false
      @server = server

      @identified = false
      if @msg_wants_id && @server.capabilities[:"identify-msg"]
        if @message =~ /^([-+])(.*)/
          @identified = ($1=="+")
          @message = $2
        else
          warning "Message does not have identification"
        end
      end
      @logmessage = @message.dup

      if target && target == @bot.myself
        @address = true
      end

    end

    # Access the nick of the source
    #
    def sourcenick
      @source.nick rescue @source.to_s
    end

    # Access the user@host of the source
    #
    def sourceaddress
      "#{@source.user}@#{@source.host}" rescue @source.to_s
    end

    # Access the botuser corresponding to the source, if any
    #
    def botuser
      source.botuser rescue @bot.auth.everyone
    end


    # Was the message from an identified user?
    def identified?
      return @identified
    end

    # returns true if the message was addressed to the bot.
    # This includes any private message to the bot, or any public message
    # which looks like it's addressed to the bot, e.g. "bot: foo", "bot, foo",
    # a kick message when bot was kicked etc.
    def address?
      return @address
    end

    # has this message been replied to by a plugin?
    def replied?
      return @replied
    end

    # strip mIRC colour escapes from a string
    def BasicUserMessage.stripcolour(string)
      return "" unless string
      ret = string.gsub(ColorRx, "")
      #ret.tr!("\x00-\x1f", "")
      ret
    end

  end

  # class for handling IRC user messages. Includes some utilities for handling
  # the message, for example in plugins.
  # The +message+ member will have any bot addressing "^bot: " removed
  # (address? will return true in this case)
  class UserMessage < BasicUserMessage

    # for plugin messages, the name of the plugin invoked by the message
    attr_reader :plugin

    # for plugin messages, the rest of the message, with the plugin name
    # removed
    attr_reader :params

    # convenience member. Who to reply to (i.e. would be sourcenick for a
    # privately addressed message, or target (the channel) for a publicly
    # addressed message
    attr_reader :replyto

    # channel the message was in, nil for privately addressed messages
    attr_reader :channel

    # for PRIVMSGs, false unless the message was a CTCP command,
    # in which case it evaluates to the CTCP command itself
    # (TIME, PING, VERSION, etc). The CTCP command parameters
    # are then stored in the message.
    attr_reader :ctcp

    # for PRIVMSGs, true if the message was a CTCP ACTION (CTCP stuff
    # will be stripped from the message)
    attr_reader :action

    # instantiate a new UserMessage
    # bot::      associated bot class
    # source::   hostmask of the message source
    # target::   nick/channel message is destined for
    # message::  message part
    def initialize(bot, server, source, target, message)
      super(bot, server, source, target, message)
      @target = target
      @private = false
      @plugin = nil
      @ctcp = false
      @action = false

      if target == @bot.myself
        @private = true
        @address = true
        @channel = nil
        @replyto = source
      else
        @replyto = @target
        @channel = @target
      end

      # check for option extra addressing prefixes, e.g "|search foo", or
      # "!version" - first match wins
      bot.config['core.address_prefix'].each {|mprefix|
        if @message.gsub!(/^#{Regexp.escape(mprefix)}\s*/, "")
          @address = true
          break
        end
      }

      # even if they used above prefixes, we allow for silly people who
      # combine all possible types, e.g. "|rbot: hello", or
      # "/msg rbot rbot: hello", etc
      if @message.gsub!(/^\s*#{Regexp.escape(bot.nick)}\s*([:;,>]|\s)\s*/i, "")
        @address = true
      end

      if(@message =~ /^\001(\S+)(\s(.+))?\001/)
        @ctcp = $1
	# FIXME need to support quoting of NULL and CR/LF, see
	# http://www.irchelp.org/irchelp/rfc/ctcpspec.html
        @message = $3 || String.new
        @action = @ctcp == 'ACTION'
        debug "Received CTCP command #{@ctcp} with options #{@message} (action? #{@action})"
        @logmessage = @message.dup
      end

      # free splitting for plugins
      @params = @message.dup
      if @params.gsub!(/^\s*(\S+)[\s$]*/, "")
        @plugin = $1.downcase
        @params = nil unless @params.length > 0
      end
    end

    # returns true for private messages, e.g. "/msg bot hello"
    def private?
      return @private
    end

    # returns true if the message was in a channel
    def public?
      return !@private
    end

    def action?
      return @action
    end

    # convenience method to reply to a message, useful in plugins. It's the
    # same as doing:
    # <tt>@bot.say m.replyto, string</tt>
    # So if the message is private, it will reply to the user. If it was
    # in a channel, it will reply in the channel.
    def plainreply(string, options={})
      @bot.say @replyto, string, options
      @replied = true
    end

    # Same as reply, but when replying in public it adds the nick of the user
    # the bot is replying to
    def nickreply(string, options={})
      extra = self.public? ? "#{@source}#{@bot.config['core.nick_postfix']} " : ""
      @bot.say @replyto, extra + string, options
      @replied = true
    end

    # the default reply style is to nickreply unless the reply already contains
    # the nick or core.reply_with_nick is set to false
    #
    def reply(string, options={})
      if @bot.config['core.reply_with_nick'] and not string =~ /\b#{Regexp.escape(@source.to_s)}\b/
        return nickreply(string, options)
      end
      plainreply(string, options)
    end

    # convenience method to reply to a message with an action. It's the
    # same as doing:
    # <tt>@bot.action m.replyto, string</tt>
    # So if the message is private, it will reply to the user. If it was
    # in a channel, it will reply in the channel.
    def act(string, options={})
      @bot.action @replyto, string, options
      @replied = true
    end

    # send a CTCP response, i.e. a private NOTICE to the sender
    # with the same CTCP command and the reply as a parameter
    def ctcp_reply(string, options={})
      @bot.ctcp_notice @source, @ctcp, string, options
    end

    # convenience method to reply "okay" in the current language to the
    # message
    def plainokay
      self.plainreply @bot.lang.get("okay")
    end

    # Like the above, but append the username
    def nickokay
      str = @bot.lang.get("okay").dup
      if self.public?
        # remove final punctuation
        str.gsub!(/[!,.]$/,"")
        str += ", #{@source}"
      end
      self.plainreply str
    end

    # the default okay style is the same as the default reply style
    #
    def okay
      if @bot.config['core.reply_with_nick']
        return nickokay
      end
      plainokay
    end

    # send a NOTICE to the message source
    #
    def notify(msg,opts={})
      @bot.notice(sourcenick, msg, opts)
    end

  end

  # class to manage IRC PRIVMSGs
  class PrivMessage < UserMessage
    def initialize(bot, server, source, target, message)
      @msg_wants_id = true
      super
    end
  end

  # class to manage IRC NOTICEs
  class NoticeMessage < UserMessage
    def initialize(bot, server, source, target, message)
      @msg_wants_id = true
      super
    end
  end

  # class to manage IRC KICKs
  # +address?+ can be used as a shortcut to see if the bot was kicked,
  # basically, +target+ was kicked from +channel+ by +source+ with +message+
  class KickMessage < BasicUserMessage
    # channel user was kicked from
    attr_reader :channel

    def initialize(bot, server, source, target, channel, message="")
      super(bot, server, source, target, message)
      @channel = channel
    end
  end

  # class to manage IRC INVITEs
  # +address?+ can be used as a shortcut to see if the bot was invited,
  # which should be true except for server bugs
  class InviteMessage < BasicUserMessage
    # channel user was invited to
    attr_reader :channel

    def initialize(bot, server, source, target, channel, message="")
      super(bot, server, source, target, message)
      @channel = channel
    end
  end

  # class to pass IRC Nick changes in. @message contains the old nickame,
  # @sourcenick contains the new one.
  class NickMessage < BasicUserMessage
    def initialize(bot, server, source, oldnick, newnick)
      super(bot, server, source, oldnick, newnick)
    end

    def oldnick
      return @target
    end

    def newnick
      return @message
    end
  end

  class QuitMessage < BasicUserMessage
    def initialize(bot, server, source, target, message="")
      super(bot, server, source, target, message)
    end
  end

  class TopicMessage < BasicUserMessage
    # channel topic
    attr_reader :topic
    # topic set at (unixtime)
    attr_reader :timestamp
    # topic set on channel
    attr_reader :channel

    def initialize(bot, server, source, channel, topic=ChannelTopic.new)
      super(bot, server, source, channel, topic.text)
      @topic = topic
      @timestamp = topic.set_on
      @channel = channel
    end
  end

  # class to manage channel joins
  class JoinMessage < BasicUserMessage
    # channel joined
    attr_reader :channel
    def initialize(bot, server, source, channel, message="")
      super(bot, server, source, channel, message)
      @channel = channel
      # in this case sourcenick is the nick that could be the bot
      @address = (source == @bot.myself)
    end
  end

  # class to manage channel parts
  # same as a join, but can have a message too
  class PartMessage < JoinMessage
  end
end
