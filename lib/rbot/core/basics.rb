#-- vim:sw=2:et
#++
#
# :title: rbot basic management from IRC
#
# Author:: Giuseppe "Oblomov" Bilotta <giuseppe.bilotta@gmail.com>

class BasicsModule < CoreBotModule

  Config.register Config::BooleanValue.new('irc.join_after_identify',
    :default => false, :wizard => true, :requires_restart => true,
    :desc => "Should the bot wait until its identification is confirmed before joining any channels?")

  # Avoiding sending WHO to any channel that we are already in.
  # Helps a LOT when you are present in a lot of channels.
  def join_channels
    existing_channels = Set.new
    # The channels array contains channels that we are invited to and not IN as
    # well. Eg, if a user without permissions invites us.
    existing_channels.merge @bot.server.channels.map { |c|
      c.has_user?(@bot.nick) ? c.name : nil
    }.compact
    # Now join the difference between the channels we are supposed to be in and
    # the ones that we are already in.
    @bot.config['irc.join_channels'].each { |c|
      if existing_channels.include?(c)
        next
      end
      debug "autojoining channel #{c}"
      if(c =~ /^(\S+)\s+(\S+)$/i)
        @bot.join $1, $2
        existing_channels << $1
      elsif(c)
        @bot.join c
        existing_channels << c
      end
    }
  end

  def identified
    join_channels
  end

  # on connect, we join the default channels unless we have to wait for
  # identification. Observe that this means the bot may not connect any channels
  # until the 'identified' method gets delegated
  def connect
    join_channels unless @bot.config['irc.join_after_identify']
  end

  def ctcp_listen(m)
    who = m.private? ? "me" : m.target
    case m.ctcp.intern
    when :PING
      m.ctcp_reply m.message
    when :TIME
      m.ctcp_reply Time.now.to_s
    end
  end

  def bot_join(m, param)
    if param[:pass]
      @bot.join param[:chan], param[:pass]
    else
      @bot.join param[:chan]
    end
  end

  def invite(m)
    if @bot.auth.allow?(:"basics::move::join", m.source, m.source)
      @bot.join m.channel
    end
  end

  def bot_part(m, param)
    if param[:chan]
      @bot.part param[:chan]
    else
      @bot.part m.target if m.public?
    end
  end
  
  def bot_rejoin(m, param)
    join_channels
  end
  
  def bot_channel_list(m, param)
    ret = 'I am in: '
    server = m.server
    nick = @bot.nick
    unless server.channels.empty?
        ret << server.channels.map{ |c|
          if c.has_user?(@bot.nick)
            "%s%s" % [
              c.modes_of(nick).map { |mo| 
                server.prefix_for_mode(mo) 
              }, 
              c.name
            ]
          else
            nil
          end
        }.compact.join(' ')
    end
    m.reply ret
  end

  def bot_quit(m, param)
    @bot.quit param[:msg].to_s
  end

  def bot_restart(m, param)
    @bot.restart param[:msg].to_s
  end

  def bot_hide(m, param)
    @bot.join 0
  end

  def bot_say(m, param)
    @bot.say param[:where], param[:what].to_s
  end

  def bot_action(m, param)
    @bot.action param[:where], param[:what].to_s
  end

  def bot_mode(m, param)
    @bot.mode param[:where], param[:what], param[:who].join(" ")
  end

  def bot_ping(m, param)
    m.reply "pong"
  end

  def bot_quiet(m, param)
    if param.has_key?(:where)
      @bot.set_quiet param[:where].sub(/^here$/, m.target.downcase)
    else
      @bot.set_quiet
    end
    # Make sense when the commmand is given in private or in a non-quieted
    # channel
    m.okay
  end

  def bot_talk(m, param)
    if param.has_key?(:where)
      @bot.reset_quiet param[:where].sub(/^here$/, m.target.downcase)
    else
      @bot.reset_quiet
    end
    # Make sense when the commmand is given in private or in a non-quieted
    # channel
    m.okay
  end

  def bot_help(m, param)
    m.reply @bot.help(param[:topic].join(" "))
  end

  #TODO move these to a "chatback" plugin
  # when (/^(botsnack|ciggie)$/i)
  #   @bot.say m.replyto, @lang.get("thanks_X") % m.sourcenick if(m.public?)
  #   @bot.say m.replyto, @lang.get("thanks") if(m.private?)
  # when (/^#{Regexp.escape(@bot.nick)}!*$/)
  #   @bot.say m.replyto, @lang.get("hello_X") % m.sourcenick

  # handle help requests for "core" topics
  def help(cmd, topic="")
    case cmd
    when "quit"
      _("quit [<message>] => quit IRC with message <message>")
    when "restart"
      _("restart => completely stop and restart the bot (including reconnect)")
    when "join"
      _("join <channel> [<key>] => join channel <channel> with secret key <key> if specified. #{@bot.myself} also responds to invites if you have the required access level")
    when "part"
      _("part <channel> => part channel <channel>")
    when "hide"
      _("hide => part all channels")
    when "say"
      _("say <channel>|<nick> <message> => say <message> to <channel> or in private message to <nick>")
    when "action"
      _("action <channel>|<nick> <message> => does a /me <message> to <channel> or in private message to <nick>")
    when "quiet"
      _("quiet [in here|<channel>] => with no arguments, stop speaking in all channels, if \"in here\", stop speaking in this channel, or stop speaking in <channel>")
    when "talk"
      _("talk [in here|<channel>] => with no arguments, resume speaking in all channels, if \"in here\", resume speaking in this channel, or resume speaking in <channel>")
    when "ping"
      _("ping => replies with a pong")
    when "mode"
      _("mode <channel> <mode> <nicks> => set channel modes for <nicks> on <channel> to <mode>")
    #     when "botsnack"
    #       return "botsnack => reward #{@bot.myself} for being good"
    #     when "hello"
    #       return "hello|hi|hey|yo [#{@bot.myself}] => greet the bot"
    else
      _("%{name}: quit, restart, join, part, hide, save, say, action, topic, quiet, talk, ping, mode") % {:name=>name}
      #, botsnack, hello
    end
  end
end

basics = BasicsModule.new

basics.map "quit *msg",
  :action => 'bot_quit',
  :defaults => { :msg => nil },
  :auth_path => 'quit'
basics.map "restart *msg",
  :action => 'bot_restart',
  :defaults => { :msg => nil },
  :auth_path => 'quit'

basics.map "quiet [in] [:where]",
  :action => 'bot_quiet',
  :auth_path => 'talk::set'
basics.map "talk [in] [:where]",
  :action => 'bot_talk',
  :auth_path => 'talk::set'

basics.map "say :where *what",
  :action => 'bot_say',
  :auth_path => 'talk::do'
basics.map "action :where *what",
  :action => 'bot_action',
  :auth_path => 'talk::do'
basics.map "mode :where :what *who",
  :action => 'bot_mode',
  :auth_path => 'talk::do'

basics.map "join :chan :pass", 
  :action => 'bot_join',
  :defaults => {:pass => nil},
  :auth_path => 'move'
basics.map "part :chan",
  :action => 'bot_part',
  :defaults => {:chan => nil},
  :auth_path => 'move'
basics.map "rejoin",
  :action => 'bot_rejoin',
  :auth_path => 'move'
basics.map "channels",
  :action => 'bot_channel_list',
  :auth_path => 'move'
basics.map "hide",
  :action => 'bot_hide',
  :auth_path => 'move'

basics.map "ping",
  :action => 'bot_ping',
  :auth_path => '!ping!'
basics.map "help *topic",
  :action => 'bot_help',
  :defaults => { :topic => [""] },
  :auth_path => '!help!'

basics.default_auth('*', false)

