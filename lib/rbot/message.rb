module Irc
  BotConfig.register BotConfigArrayValue.new('core.address_prefix',
    :default => [], :wizard => true,
    :desc => "what non nick-matching prefixes should the bot respond to as if addressed (e.g !, so that '!foo' is treated like 'rbot: foo')"
  )

  Color = "\003"
  Bold = "\002"
  Underline = "\037"
  Reverse = "\026"

  # base user message class, all user messages derive from this
  # (a user message is defined as having a source hostmask, a target
  # nick/channel and a message part)
  class BasicUserMessage

    # associated bot
    attr_reader :bot

    # when the message was received
    attr_reader :time

    # hostmask of message source
    attr_reader :source

    # nick of message source
    attr_reader :sourcenick

    # url part of message source
    attr_reader :sourceaddress

    # nick/channel message was sent to
    attr_reader :target

    # contents of the message
    attr_accessor :message

    # has the message been replied to/handled by a plugin?
    attr_accessor :replied

    # instantiate a new Message
    # bot::      associated bot class
    # source::   hostmask of the message source
    # target::   nick/channel message is destined for
    # message::  message part
    def initialize(bot, source, target, message)
      @msg_wants_id = false unless defined? @msg_wants_id

      @time = Time.now
      @bot = bot
      @source = source
      @address = false
      @target = target
      @message = BasicUserMessage.stripcolour message
      @replied = false

      @identified = false
      if @msg_wants_id && @bot.capabilities["identify-msg".to_sym]
        if @message =~ /([-+])(.*)/
          @identified = ($1=="+")
          @message = $2
        else
          warning "Message does not have identification"
        end
      end

      # split source into consituent parts
      if source =~ /^((\S+)!(\S+))$/
        @sourcenick = $2
        @sourceaddress = $3
      end

      if target && target.downcase == @bot.nick.downcase
        @address = true
      end

    end

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
      ret = string.gsub(/\cC\d\d?(?:,\d\d?)?/, "")
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

    # for PRIVMSGs, true if the message was a CTCP ACTION (CTCP stuff
    # will be stripped from the message)
    attr_reader :action

    # instantiate a new UserMessage
    # bot::      associated bot class
    # source::   hostmask of the message source
    # target::   nick/channel message is destined for
    # message::  message part
    def initialize(bot, source, target, message)
      super(bot, source, target, message)
      @target = target
      @private = false
      @plugin = nil
      @action = false

      if target.downcase == @bot.nick.downcase
        @private = true
        @address = true
        @channel = nil
        @replyto = @sourcenick
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

      if(@message =~ /^\001ACTION\s(.+)\001/)
        @message = $1
        @action = true
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
    def reply(string)
      @bot.say @replyto, string
      @replied = true
    end

    # convenience method to reply to a message with an action. It's the
    # same as doing:
    # <tt>@bot.action m.replyto, string</tt>
    # So if the message is private, it will reply to the user. If it was
    # in a channel, it will reply in the channel.
    def act(string)
      @bot.action @replyto, string
      @replied = true
    end

    # convenience method to reply "okay" in the current language to the
    # message
    def okay
      @bot.say @replyto, @bot.lang.get("okay")
    end

  end

  # class to manage IRC PRIVMSGs
  class PrivMessage < UserMessage
    def initialize(bot, source, target, message)
      @msg_wants_id = true
      super
    end
  end

  # class to manage IRC NOTICEs
  class NoticeMessage < UserMessage
    def initialize(bot, source, target, message)
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

    def initialize(bot, source, target, channel, message="")
      super(bot, source, target, message)
      @channel = channel
    end
  end

  # class to pass IRC Nick changes in. @message contains the old nickame,
  # @sourcenick contains the new one.
  class NickMessage < BasicUserMessage
    def initialize(bot, source, oldnick, newnick)
      super(bot, source, oldnick, newnick)
    end
  end

  class QuitMessage < BasicUserMessage
    def initialize(bot, source, target, message="")
      super(bot, source, target, message)
    end
  end

  class TopicMessage < BasicUserMessage
    # channel topic
    attr_reader :topic
    # topic set at (unixtime)
    attr_reader :timestamp
    # topic set on channel
    attr_reader :channel

    def initialize(bot, source, channel, timestamp, topic="")
      super(bot, source, channel, topic)
      @topic = topic
      @timestamp = timestamp
      @channel = channel
    end
  end

  # class to manage channel joins
  class JoinMessage < BasicUserMessage
    # channel joined
    attr_reader :channel
    def initialize(bot, source, channel, message="")
      super(bot, source, channel, message)
      @channel = channel
      # in this case sourcenick is the nick that could be the bot
      @address = (sourcenick.downcase == @bot.nick.downcase)
    end
  end

  # class to manage channel parts
  # same as a join, but can have a message too
  class PartMessage < JoinMessage
  end
end
