#-- vim:sw=2:et
#++
#
# :title: Bans Plugin v3 for rbot 0.9.11 and later
#
# Author:: Marco Gulino <marco@kmobiletools.org>
# Author:: kamu <mr.kamu@gmail.com>
# Author:: Giuseppe Bilotta <giuseppe.bilotta@gmail.com>
#
# Copyright:: (C) 2006 Marco Gulino
# Copyright:: (C) 2007 kamu, Giuseppe Bilotta
#
# License:: GPL V2.
#
# Managing kick and bans, automatically removing bans after timeouts, quiet
# bans, and kickban/quietban based on regexp
#
# v1 -> v2 (kamu's version, never released)
#   * reworked
#   * autoactions triggered on join
#   * action on join or badword can be anything: kick, ban, kickban, quiet
#
# v2 -> v3 (GB)
#   * remove the 'bans' prefix from most of the commands
#   * (un)quiet has been renamed to (un)silence because 'quiet' was used to
#     tell the bot to keep quiet
#   * both (un)quiet and (un)silence are accepted as actions
#   * use the more descriptive 'onjoin' term for autoactions
#   * convert v1's (0.9.10) :bans and :bansmasks to BadWordActions and
#     WhitelistEntries
#   * enhanced list manipulation facilities
#   * fixed regexp usage in requirements for plugin map
#   * add proper auth management

define_structure :OnJoinAction, :host, :action, :channel, :reason
define_structure :BadWordAction, :regexp, :action, :channel, :timer, :reason
define_structure :WhitelistEntry, :host, :channel
define_structure :MassHlAction, :num, :perc, :action, :channel, :timer, :reason

class BansPlugin < Plugin

  IdxRe = /^\d+$/
  TimerRe = /^\d+[smhd]$/
  ChannelRe = /^#+[^\s]+$/
  ChannelAllRe = /^(?:all|#+[^\s]+)$/
  ActionRe = /(?:ban|kick|kickban|silence|quiet)/

  def name
    "bans"
  end

  def make_badword_rx(txt)
    return /\b(?:#{txt})\b/i
  end

  def initialize
    super

    # Convert old BadWordActions, which were simpler and labelled :bans
    if @registry.has_key? :bans
      badwords = Array.new
      bans = @registry[:bans]
      @registry[:bans].each { |ar|
        case ar[0]
        when "quietban"
          action = :silence
        when "kickban"
          action = :kickban
        else
          # Shouldn't happen
          warning "Unknown action in old data #{ar.inspect} -- entry ignored"
          next
        end
        bans.delete(ar)
        chan = ar[1].downcase
        regexp = make_badword_rx(ar[2])
        badwords << BadWordAction.new(regexp, action, chan, "0s", "")
      }
      @registry[:badwords] = badwords
      if bans.length > 0
        # Store the ones we couldn't convert
        @registry[:bans] = bans
      else
        @registry.delete(:bans)
      end
    else
      @registry[:badwords] = Array.new unless @registry.has_key? :badwords
    end

    # Convert old WhitelistEntries, which were simpler and labelled :bansmasks
    if @registry.has_key? :bans
      wl = Array.new
      @registry[:bansmasks].each { |mask|
        badwords << WhitelistEntry.new(mask, "all")
      }
      @registry[:whitelist] = wl
      @registry.delete(:bansmasks)
    else
      @registry[:whitelist] = Array.new unless @registry.has_key? :whitelist
    end

    @registry[:onjoin] = Array.new unless @registry.has_key? :onjoin
    @registry[:masshl] = Array.new unless @registry.has_key? :masshl
  end

  def help(plugin, topic="")
    case plugin
    when "ban"
      return "ban <nick/hostmask> [Xs/m/h/d] [#channel]: ban a user from the given channel for the given amount of time. default is forever, on the current channel"
    when "unban"
      return "unban <nick/hostmask> [#channel]: unban a user from the given channel. defaults to the current channel"
    when "kick"
      return "kick <nick> [#channel] [reason ...]: kick a user from the given channel with the given reason. defaults to the current channel, no reason"
    when "kickban"
      return "kickban <nick> [Xs/m/h/d] [#channel] [reason ...]: kicks and bans a user from the given channel for the given amount of time, with the given reason. default is forever, on the current channel, with no reason"
    when "silence"
      return "silence <nick/hostmask> [Xs/m/h/d] [#channel]: silence a user on the given channel for the given time. default is forever, on the current channel. not all servers support silencing users"
    when "unsilence"
      return "unsilence <nick/hostmask> [#channel]: allow the given user to talk on the given channel. defaults to the current channel"
    when "bans"
      case topic
      when "add"
        return "bans add <onjoin|badword|whitelist|masshl>: add an automatic action for people that join or say some bad word, or a whitelist entry. further help available"
      when "add onjoin"
        return "bans add onjoin <hostmask> [action] [#channel] [reason ...]: will add an autoaction for any one who joins with hostmask. default action is silence, default channel is all"
      when "add badword"
        return "bans add badword <regexp> [action] [Xs/m/h/d] [#channel|all] [reason ...]: adds a badword regexp, if a user sends a message that matches regexp, the action will be invoked. default action is silence, default channel is all"
      when "add whitelist"
        return "bans add whitelist <hostmask> [#channel|all]: add the given hostmask to the whitelist. no autoaction will be triggered by users on the whitelist"
      when "add masshl"
        return "masshl add <max_nicks|percentage> [action] [Xs/m/h/d] [#channel|all] [reason ...]: adds an massive highligh action. You can use both max and % in one trigger, the higher value will be taken. For two triggers in one channel, the one with higher requirements will be taken"
      when "rm"
        return "bans rm <onjoin|badword|whitelist> <hostmask/regexp> [#channel], or bans rm <onjoin|badword|whitelist> index <num>: removes the specified onjoin or badword rule or whitelist entry. For masshl, bans rm masshl index [#channel|all]"
      when "list"
        return"bans list <onjoin|badword|whitelist|masshl>: lists all onjoin or badwords or whitelist entries. For masshl, you can add [#channel|all]"
      else
        return "commands are: add, add onjoin, add badword, add whitelist, add masshl, rm, list"
      end
    end
    return "bans <command>: allows a user of the bot to do a range of bans and unbans. commands are: [un]ban, kick[ban], [un]silence, add, rm and list"
  end

  def message(m)
    return unless m.channel

    # check the whitelist first
    @registry[:whitelist].each { |white|
      next unless ['all', m.target.downcase].include?(white.channel)
      return if m.source.matches?(white.host)
    }

    # check the badwords next
    @registry[:badwords].each { |badword|
      next unless ['all', m.target.downcase].include?(badword.channel)
      next unless badword.regexp.match(m.plainmessage)

      m.reply "bad word detected! #{badword.action} for #{badword.timer} because: #{badword.reason}"
      do_cmd(badword.action.to_sym, m.source.nick, m.target, badword.timer, badword.reason)
      return
    }

    # and finally, see if the user triggered masshl
    mm = m.plainmessage.irc_downcase(m.server.casemap).split(/[\s\.,:]/)
    nicks_said = (m.channel.users.map { |u| u.downcase} & mm).size
    return unless nicks_said > 0 # not really needed, but saves some cycles
    got_nicks = 0
    masshl_action = nil
    @registry[:masshl].each { |masshl|
      next unless masshl.channel == m.channel.downcase or masshl.channel == "all"
      needed = [masshl.num.to_i, (masshl.perc * m.channel.user_nicks.size / 100).to_i].max
      next if needed > nicks_said or needed < got_nicks
      masshl_action = masshl
      got_nicks = needed
    }
    return unless masshl_action
    do_cmd masshl_action.action.intern, m.sourcenick, m.channel, masshl_action.timer, masshl_action.reason
  end

  def join(m)
    @registry[:whitelist].each { |white|
      next unless ['all', m.target.downcase].include?(white.channel)
      return if m.source.matches?(white.host)
    }

    @registry[:onjoin].each { |auto|
      next unless ['all', m.target.downcase].include?(auto.channel)
      next unless m.source.matches? auto.host

      do_cmd(auto.action.to_sym, m.source.nick, m.target, "0s", auto.reason)
      return
    }
  end

  def ban_user(m, params=nil)
    nick, channel = params[:nick], check_channel(m, params[:channel])
    timer = params[:timer]
    do_cmd(:ban, nick, channel, timer)
  end

  def unban_user(m, params=nil)
    nick, channel = params[:nick], check_channel(m, params[:channel])
    do_cmd(:unban, nick, channel)
  end

  def kick_user(m, params=nil)
    nick, channel = params[:nick], check_channel(m, params[:channel])
    reason = params[:reason].to_s
    do_cmd(:kick, nick, channel, "0s", reason)
  end

  def kickban_user(m, params=nil)
    nick, channel, reason = params[:nick], check_channel(m, params[:channel])
    timer, reason = params[:timer], params[:reason].to_s
    do_cmd(:kickban, nick, channel, timer, reason)
  end

  def silence_user(m, params=nil)
    nick, channel = params[:nick], check_channel(m, params[:channel])
    timer = params[:timer]
    do_cmd(:silence, nick, channel, timer)
  end

  def unsilence_user(m, params=nil)
    nick, channel = params[:nick], check_channel(m, params[:channel])
    do_cmd(:unsilence, nick, channel)
  end

  def add_masshl(m, params=nil)
    num = params[:num].to_i
    perc = params[:perc] ? /(\d{1,2})\%/.match(params[:perc])[1].to_i : 0
    channel, action = params[:channel].downcase.dup, params[:action]
    timer, reason = params[:timer].dup, params[:reason].to_s
    if perc == 0 and num == 0
      m.reply "both triggers 0, you don't want this."
      return
    end

    masshl = @registry[:masshl]
    masshl << MassHlAction.new(num, perc, action, channel, timer, reason)
    @registry[:masshl] = masshl

    m.okay
  end

  def rm_masshl(m, params=nil)
    masshl = @registry[:masshl]
    masshl_w = params[:channel] ? masshl.select { |mh| mh.channel == params[:channel].downcase } : masshl
    count = masshl_w.length
    idx = params[:idx].to_i

    if idx > count
      m.reply "No such masshl \##{idx}"
      return
    end
    masshl.delete(masshl_w[idx-1])
    @registry[:masshl] = masshl
    m.okay
  end

  def list_masshl(m, params=nil)
    masshl = @registry[:masshl]
    masshl = masshl.select { |mh| mh.channel == params[:channel].downcase } if params[:channel]
    m.reply params[:channel] ? "masshl rules: #{masshl.length} for #{params[:channel]}" : "masshl rules: #{masshl.length}"
    masshl.each_with_index { |mh, idx|
      m.reply "\##{idx+1}: #{mh.num} | #{mh.perc}% | #{mh.action} | #{mh.channel} | #{mh.timer} | #{mh.reason}"
    }
  end

  def add_onjoin(m, params=nil)
    begin
      host, channel = m.server.new_netmask(params[:host]), params[:channel].downcase
      action, reason = params[:action], params[:reason].to_s

      autos = @registry[:onjoin]
      autos << OnJoinAction.new(host, action, channel, reason.dup)
      @registry[:onjoin] = autos

      m.okay
    rescue
      error $!
      m.reply $!
    end
  end

  def list_onjoin(m, params=nil)
    m.reply "onjoin rules: #{@registry[:onjoin].length}"
    @registry[:onjoin].each_with_index { |auto, idx|
      m.reply "\##{idx+1}: #{auto.host} | #{auto.action} | #{auto.channel} | '#{auto.reason}'"
    }
  end

  def rm_onjoin(m, params=nil)
    autos = @registry[:onjoin]
    count = autos.length

    idx = nil
    idx = params[:idx].to_i if params[:idx]

    if idx
      if idx > count
        m.reply "No such onjoin \##{idx}"
        return
      end
      autos.delete_at(idx-1)
    else
      begin
        host = m.server.new_netmask(params[:host])
        channel = params[:channel].downcase

        autos.each { |rule|
          next unless ['all', rule.channel].include?(channel)
          autos.delete rule if rule.host == host
        }
      rescue
        error $!
        m.reply $!
      end
    end
    @registry[:onjoin] = autos
    if count > autos.length
      m.okay
    else
      m.reply "No matching onjoin rule for #{host} found"
    end
  end

  def add_badword(m, params=nil)
    regexp, channel = make_badword_rx(params[:regexp]), params[:channel].downcase.dup
    action, timer, reason = params[:action], params[:timer].dup, params[:reason].to_s

    badwords = @registry[:badwords]
    badwords << BadWordAction.new(regexp, action, channel, timer, reason)
    @registry[:badwords] = badwords

    m.okay
  end

  def list_badword(m, params=nil)
    m.reply "badword rules: #{@registry[:badwords].length}"

    @registry[:badwords].each_with_index { |badword, idx|
      m.reply "\##{idx+1}: #{badword.regexp.source} | #{badword.action} | #{badword.channel} | #{badword.timer} | #{badword.reason}"
    }
  end

  def rm_badword(m, params=nil)
    badwords = @registry[:badwords]
    count = badwords.length

    idx = nil
    idx = params[:idx].to_i if params[:idx]

    if idx
      if idx > count
        m.reply "No such badword \##{idx}"
        return
      end
      badwords.delete_at(idx-1)
    else
      channel = params[:channel].downcase

      regexp = make_badword_rx(params[:regexp])
      debug "Trying to remove #{regexp.inspect} from #{badwords.inspect}"

      badwords.each { |badword|
        next unless ['all', badword.channel].include?(channel)
        debug "Removing #{badword.inspect}" if badword.regexp == regexp
        badwords.delete(badword) if badword.regexp == regexp
      }
    end

    @registry[:badwords] = badwords
    if count > badwords.length
      m.okay
    else
      m.reply "No matching badword #{regexp} found"
    end
  end

  def add_whitelist(m, params=nil)
    begin
      host, channel = m.server.new_netmask(params[:host]), params[:channel].downcase

      # TODO check if a whitelist entry for this host already exists
      whitelist = @registry[:whitelist]
      whitelist << WhitelistEntry.new(host, channel)
      @registry[:whitelist] = whitelist

      m.okay
    rescue
      error $!
      m.reply $!
    end
  end

  def list_whitelist(m, params=nil)
    m.reply "whitelist entries: #{@registry[:whitelist].length}"
    @registry[:whitelist].each_with_index { |auto, idx|
      m.reply "\##{idx+1}: #{auto.host} | #{auto.channel}"
    }
  end

  def rm_whitelist(m, params=nil)
    wl = @registry[:whitelist]
    count = wl.length

    idx = nil
    idx = params[:idx].to_i if params[:idx]

    if idx
      if idx > count
        m.reply "No such whitelist entry \##{idx}"
        return
      end
      wl.delete_at(idx-1)
    else
      begin
        host = m.server.new_netmask(params[:host])
        channel = params[:channel].downcase

        wl.each { |rule|
          next unless ['all', rule.channel].include?(channel)
          wl.delete rule if rule.host == host
        }
      rescue
        error $!
        m.reply $!
      end
    end
    @registry[:whitelist] = wl
    if count > whitelist.length
      m.okay
    else
      m.reply "No host matching #{host}"
    end
  end

  private
  def check_channel(m, strchannel)
    begin
      raise "must specify channel if using privmsg" if m.private? and not strchannel
      channel = m.server.channel(strchannel) || m.target
      raise "I am not in that channel" unless channel.has_user?(@bot.nick)

      return channel
    rescue
      error $!
      m.reply $!
    end
  end

  def do_cmd(action, nick, channel, timer_in=nil, reason=nil)
    case timer_in
    when nil
      timer = 0
    when /^(\d+)s$/
      timer = $1.to_i
    when /^(\d+)m$/
      timer = $1.to_i * 60
    when /^(\d+)h$/
      timer = $1.to_i * 60 * 60
    when /^(\d+)d$/
      timer = $1.to_i * 60 * 60 * 24
    else
      raise "Wrong time specifications"
    end

    case action
    when :ban
      set_temporary_mode(channel, 'b', nick, timer)
    when :unban
      set_mode(channel, "-b", nick)
    when :kick
      do_kick(channel, nick, reason)
    when :kickban
      set_temporary_mode(channel, 'b', nick, timer)
      do_kick(channel, nick, reason)
    when :silence, :quiet
      set_mode(channel, "+q", nick)
      @bot.timer.add_once(timer) { set_mode(channel, "-q", nick) } if timer > 0
    when :unsilence, :unquiet
      set_mode(channel, "-q", nick)
    end
  end

  def set_mode(channel, mode, nick)
    host = channel.has_user?(nick) ? "*!*@" + channel.get_user(nick).host : nick
    @bot.mode(channel, mode, host)
  end

  def set_temporary_mode(channel, mode, nick, timer)
    host = channel.has_user?(nick) ? "*!*@" + channel.users[nick].host : nick
    @bot.mode(channel, "+#{mode}", host)
    return if timer == 0
    @bot.timer.add_once(timer) { @bot.mode(channel, "-#{mode}", host) }
  end

  def do_kick(channel, nick, reason="")
    @bot.kick(channel, nick, reason)
  end
end

plugin = BansPlugin.new

plugin.default_auth( 'act', false )
plugin.default_auth( 'edit', false )
plugin.default_auth( 'list', true )

plugin.map 'ban :nick :timer :channel', :action => 'ban_user',
  :requirements => {:timer => BansPlugin::TimerRe, :channel => BansPlugin::ChannelRe},
  :defaults => {:timer => nil, :channel => nil},
  :auth_path => 'act'
plugin.map 'unban :nick :channel', :action => 'unban_user',
  :requirements => {:channel => BansPlugin::ChannelRe},
  :defaults => {:channel => nil},
  :auth_path => 'act'
plugin.map 'kick :nick :channel *reason', :action => 'kick_user',
  :requirements => {:channel => BansPlugin::ChannelRe},
  :defaults => {:channel => nil, :reason => 'requested'},
  :auth_path => 'act'
plugin.map 'kickban :nick :timer :channel *reason', :action => 'kickban_user',
  :requirements => {:timer => BansPlugin::TimerRe, :channel => BansPlugin::ChannelRe},
  :defaults => {:timer => nil, :channel => nil, :reason => 'requested'},
  :auth_path => 'act'
plugin.map 'silence :nick :timer :channel', :action => 'silence_user',
  :requirements => {:timer => BansPlugin::TimerRe, :channel => BansPlugin::ChannelRe},
  :defaults => {:timer => nil, :channel => nil},
  :auth_path => 'act'
plugin.map 'unsilence :nick :channel', :action => 'unsilence_user',
  :requirements => {:channel => BansPlugin::ChannelRe},
  :defaults => {:channel => nil},
  :auth_path => 'act'

plugin.map 'bans add onjoin :host :action :channel *reason', :action => 'add_onjoin',
  :requirements => {:action => BansPlugin::ActionRe, :channel => BansPlugin::ChannelAllRe},
  :defaults => {:action => 'kickban', :channel => 'all', :reason => 'netmask not welcome'},
  :auth_path => 'edit::onjoin'
plugin.map 'bans rm onjoin index :idx', :action => 'rm_onjoin',
  :requirements => {:num => BansPlugin::IdxRe},
  :auth_path => 'edit::onjoin'
plugin.map 'bans rm onjoin :host :channel', :action => 'rm_onjoin',
  :requirements => {:channel => BansPlugin::ChannelAllRe},
  :defaults => {:channel => 'all'},
  :auth_path => 'edit::onjoin'
plugin.map 'bans list onjoin[s]', :action => 'list_onjoin',
  :auth_path => 'list::onjoin'

plugin.map 'bans add badword :regexp :action :timer :channel *reason', :action => 'add_badword',
  :requirements => {:action => BansPlugin::ActionRe, :timer => BansPlugin::TimerRe, :channel => BansPlugin::ChannelAllRe},
  :defaults => {:action => 'silence', :timer => "0s", :channel => 'all', :reason => 'bad word'},
  :auth_path => 'edit::badword'
plugin.map 'bans rm badword index :idx', :action => 'rm_badword',
  :requirements => {:num => BansPlugin::IdxRe},
  :auth_path => 'edit::badword'
plugin.map 'bans rm badword :regexp :channel', :action => 'rm_badword',
  :requirements => {:channel => BansPlugin::ChannelAllRe},
  :defaults => {:channel => 'all'},
  :auth_path => 'edit::badword'
plugin.map 'bans list badword[s]', :action => 'list_badword',
  :auth_path => 'list::badword'

plugin.map 'bans add whitelist :host :channel', :action => 'add_whitelist',
  :requirements => {:channel => BansPlugin::ChannelAllRe},
  :defaults => {:channel => 'all'},
  :auth_path => 'edit::whitelist'
plugin.map 'bans rm whitelist index :idx', :action => 'rm_whitelist',
  :requirements => {:num => BansPlugin::IdxRe},
  :auth_path => 'edit::whitelist'
plugin.map 'bans rm whitelist :host :channel', :action => 'rm_whitelist',
  :requirements => {:channel => BansPlugin::ChannelAllRe},
  :defaults => {:channel => 'all'},
  :auth_path => 'edit::whitelist'
plugin.map 'bans list whitelist', :action => 'list_whitelist',
  :auth_path => 'list::whitelist'

plugin.map 'bans add masshl :num :perc :action :timer :channel *reason', :action => 'add_masshl',
  :requirements => {:num => /\d{1,2}/, :perc => /\d{1,2}\%/,:action => BansPlugin::ActionRe, :timer => BansPlugin::TimerRe, :channel => BansPlugin::ChannelAllRe},
  :defaults => {:action => 'silence', :timer => "0s", :channel => 'all', :reason => 'masshl'},
  :auth_path => 'edit::masshl'
plugin.map 'bans add masshl :perc :num :action :timer :channel *reason', :action => 'add_masshl',
  :requirements => {:num => /\d{1,2}/, :perc => /\d{1,2}\%/,:action => BansPlugin::ActionRe, :timer => BansPlugin::TimerRe, :channel => BansPlugin::ChannelAllRe},
  :defaults => {:action => 'silence', :timer => "0s", :channel => 'all', :reason => 'masshl'},
  :auth_path => 'edit::masshl'
plugin.map 'bans add masshl :perc :action :timer :channel *reason', :action => 'add_masshl',
  :requirements => {:num => /\d{1,2}/, :perc => /\d{1,2}\%/,:action => BansPlugin::ActionRe, :timer => BansPlugin::TimerRe, :channel => BansPlugin::ChannelAllRe},
  :defaults => {:num => 0, :action => 'silence', :timer => "0s", :channel => 'all', :reason => 'masshl'},
  :auth_path => 'edit::masshl'
plugin.map 'bans add masshl :num :action :timer :channel *reason', :action => 'add_masshl',
  :requirements => {:num => /\d{1,2}/, :perc => /\d{1,2}\%/,:action => BansPlugin::ActionRe, :timer => BansPlugin::TimerRe, :channel => BansPlugin::ChannelAllRe},
  :defaults => {:perc => "0%", :action => 'silence', :timer => "0s", :channel => 'all', :reason => 'masshl'},
  :auth_path => 'edit::masshl'
plugin.map 'bans rm masshl :idx', :action => 'rm_masshl',
  :requirements => {:channel => nil, :num => BansPlugin::IdxRe},
  :auth_path => 'edit::masshl'
plugin.map 'bans rm masshl :idx :channel', :action => 'rm_masshl',
  :requirements => {:channel => BansPlugin::ChannelAllRe},
  :defaults => {:channel => nil},
  :auth_path => 'edit::masshl'
plugin.map 'bans list masshl', :action => 'list_masshl',
  :auth_path => 'list::masshl'
plugin.map 'bans list masshl :channel', :action => 'list_masshl',
  :defaults => {:channel => nil},
  :auth_path => 'list::masshl'
