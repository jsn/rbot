#-- vim:sw=2:et
#++
#
# :title: rbot auth management from IRC
#
# Author:: Giuseppe "Oblomov" Bilotta <giuseppe.bilotta@gmail.com>
# Copyright:: (C) 2006,2007 Giuseppe Bilotta
# License:: GPL v2

class AuthModule < CoreBotModule

  def initialize
    super

    # The namespace migration causes each Irc::Auth::PermissionSet to be
    # unrecoverable, and we have to rename their class name to
    # Irc::Bot::Auth::PermissionSet
    @registry.recovery = Proc.new { |val|
      patched = val.sub("o:\035Irc::Auth::PermissionSet", "o:\042Irc::Bot::Auth::PermissionSet")
      Marshal.restore(patched)
    }

    load_array(:default, true)
    debug "initialized auth. Botusers: #{@bot.auth.save_array.pretty_inspect}"
  end

  def save
    save_array
  end

  def save_array(key=:default)
    if @bot.auth.changed?
      @registry[key] = @bot.auth.save_array
      @bot.auth.reset_changed
      debug "saved botusers (#{key}): #{@registry[key].pretty_inspect}"
    end
  end

  def load_array(key=:default, forced=false)
    debug "loading botusers (#{key}): #{@registry[key].pretty_inspect}"
    @bot.auth.load_array(@registry[key], forced) if @registry.has_key?(key)
  end

  # The permission parameters accept arguments with the following syntax:
  #   cmd_path... [on #chan .... | in here | in private]
  # This auxiliary method scans the array _ar_ to see if it matches
  # the given syntax: it expects + or - signs in front of _cmd_path_
  # elements when _setting_ = true
  #
  # It returns an array whose first element is the array of cmd_path,
  # the second element is an array of locations and third an array of
  # warnings occurred while parsing the strings
  #
  def parse_args(ar, setting)
    cmds = []
    locs = []
    warns = []
    doing_cmds = true
    next_must_be_chan = false
    want_more = false
    last_idx = 0
    ar.each_with_index { |x, i|
      if doing_cmds # parse cmd_path
        # check if the list is done
        if x == "on" or x == "in"
          doing_cmds = false
          next_must_be_chan = true if x == "on"
          next
        end
        if "+-".include?(x[0])
          warns << ArgumentError.new(_("please do not use + or - in front of command %{command} when resetting") % {:command => x}) unless setting
        else
          warns << ArgumentError.new(_("+ or - expected in front of %{string}") % {:string => command}) if setting
        end
        cmds << x
      else # parse locations
        if x[-1].chr == ','
          want_more = true
        else
          want_more = false
        end
        case next_must_be_chan
        when false
          locs << x.gsub(/^here$/,'_').gsub(/^private$/,'?')
        else
          warns << ArgumentError.new(_("'%{string}' doesn't look like a channel name") % {:string => x}) unless @bot.server.supports[:chantypes].include?(x[0])
          locs << x
        end
        unless want_more
          last_idx = i
          break
        end
      end
    }
    warns << _("trailing comma") if want_more
    warns << _("you probably forgot a comma") unless last_idx == ar.length - 1
    return cmds, locs, warns
  end

  def auth_edit_perm(m, params)

    setting = m.message.split[1] == "set"
    splits = params[:args]

    has_for = splits[-2] == "for"
    return usage(m) unless has_for

    begin
      user = @bot.auth.get_botuser(splits[-1].sub(/^all$/,"everyone"))
    rescue
      return m.reply(_("couldn't find botuser %{name}") % {:name => splits[-1]})
    end
    return m.reply(_("you can't change permissions for %{username}") % {:username => user.username}) if user.owner?
    splits.slice!(-2,2) if has_for

    cmds, locs, warns = parse_args(splits, setting)
    errs = warns.select { |w| w.kind_of?(Exception) }

    unless errs.empty?
      m.reply _("couldn't satisfy your request: %{errors}") % {:errors => errs.join(',')}
      return
    end

    if locs.empty?
      locs << "*"
    end
    begin
      locs.each { |loc|
        ch = loc
        if m.private?
          ch = "?" if loc == "_"
        else
          ch = m.target.to_s if loc == "_"
        end
        cmds.each { |setval|
          if setting
            val = setval[0].chr == '+'
            cmd = setval[1..-1]
            user.set_permission(cmd, val, ch)
          else
            cmd = setval
            user.reset_permission(cmd, ch)
          end
        }
      }
    rescue => e
      m.reply "something went wrong while trying to set the permissions"
      raise
    end
    @bot.auth.set_changed
    debug "user #{user} permissions changed"
    m.okay
  end

  def auth_view_perm(m, params)
    begin
      if params[:user].nil?
        user = get_botusername_for(m.source)
        return m.reply(_("you are owner, you can do anything")) if user.owner?
      else
        user = @bot.auth.get_botuser(params[:user].sub(/^all$/,"everyone"))
        return m.reply(_("owner can do anything")) if user.owner?
      end
    rescue
      return m.reply(_("couldn't find botuser %{name}") % {:name => params[:user]})
    end
    perm = user.perm
    str = []
    perm.each { |k, val|
      next if val.perm.empty?
      case k
      when :*
        str << _("on any channel: ")
      when :"?"
        str << _("in private: ")
      else
        str << _("on #{k}: ")
      end
      sub = []
      val.perm.each { |cmd, bool|
        sub << (bool ? "+" : "-")
        sub.last << cmd.to_s
      }
      str.last << sub.join(', ')
    }
    if str.empty?
      m.reply _("no permissions set for %{user}") % {:user => user.username}
    else
      m.reply _("permissions for %{user}:: %{permissions}") %
              { :user => user.username, :permissions => str.join('; ')}
    end
  end

  def get_botuser_for(user)
    @bot.auth.irc_to_botuser(user)
  end

  def get_botusername_for(user)
    get_botuser_for(user).username
  end

  def welcome(user)
    _("welcome, %{user}") % {:user => get_botusername_for(user)}
  end

  def auth_auth(m, params)
    params[:botuser] = 'owner'
    auth_login(m,params)
  end

  def auth_login(m, params)
    begin
      case @bot.auth.login(m.source, params[:botuser], params[:password])
      when true
        m.reply welcome(m.source)
        @bot.auth.set_changed
      else
        m.reply _("sorry, can't do")
      end
    rescue => e
      m.reply _("couldn't login: %{exception}") % {:exception => e}
      raise
    end
  end

  def auth_autologin(m, params)
    u = do_autologin(m.source)
    if u.default?
      m.reply _("I couldn't find anything to let you login automatically")
    else
      m.reply welcome(m.source)
    end
  end

  def do_autologin(user)
    @bot.auth.autologin(user)
  end

  def auth_whoami(m, params)
    m.reply _("you are %{who}") % {
      :who => get_botusername_for(m.source).gsub(
                /^everyone$/, _("no one that I know")).gsub(
                /^owner$/, _("my boss"))
    }
  end

  def auth_whois(m, params)
    return auth_whoami(m, params) if !m.public?
    u = m.channel.users[params[:user]]

    return m.reply("I don't see anyone named '#{params[:user]}' here") unless u

    m.reply _("#{params[:user]} is %{who}") % {
      :who => get_botusername_for(u).gsub(
                /^everyone$/, _("no one that I know")).gsub(
                /^owner$/, _("my boss"))
    }
  end

  def help(cmd, topic="")
    case cmd
    when "login"
      return _("login [<botuser>] [<pass>]: logs in to the bot as botuser <botuser> with password <pass>. When using the full form, you must contact the bot in private. <pass> can be omitted if <botuser> allows login-by-mask and your netmask is among the known ones. if <botuser> is omitted too autologin will be attempted")
    when "whoami"
      return _("whoami: names the botuser you're linked to")
    when "who"
      return _("who is <user>: names the botuser <user> is linked to")
    when /^permission/
      case topic
      when "syntax"
        return _("a permission is specified as module::path::to::cmd; when you want to enable it, prefix it with +; when you want to disable it, prefix it with -; when using the +reset+ command, do not use any prefix")
      when "set", "reset", "[re]set", "(re)set"
        return _("permissions [re]set <permission> [in <channel>] for <user>: sets or resets the permissions for botuser <user> in channel <channel> (use ? to change the permissions for private addressing)")
      when "view"
        return _("permissions view [for <user>]: display the permissions for user <user>")
      else
        return _("permission topics: syntax, (re)set, view")
      end
    when "user"
      case topic
      when "show"
        return _("user show <what> : shows info about the user; <what> can be any of autologin, login-by-mask, netmasks")
      when /^(en|dis)able/
        return _("user enable|disable <what> : turns on or off <what> (autologin, login-by-mask)")
      when "set"
        return _("user set password <blah> : sets the user password to <blah>; passwords can only contain upper and lowercase letters and numbers, and must be at least 4 characters long")
      when "add", "rm"
        return _("user add|rm netmask <mask> : adds/removes netmask <mask> from the list of netmasks known to the botuser you're linked to")
      when "reset"
        return _("user reset <what> : resets <what> to the default values. <what> can be +netmasks+ (the list will be emptied), +autologin+ or +login-by-mask+ (will be reset to the default value) or +password+ (a new one will be generated and you'll be told in private)")
      when "tell"
        return _("user tell <who> the password for <botuser> : contacts <who> in private to tell him/her the password for <botuser>")
      when "create"
        return _("user create <name> <password> : create botuser named <name> with password <password>. The password can be omitted, in which case a random one will be generated. The <name> should only contain alphanumeric characters and the underscore (_)")
      when "list"
        return _("user list : lists all the botusers")
      when "destroy"
        return _("user destroy <botuser> : destroys <botuser>. This function %{highlight}must%{highlight} be called in two steps. On the first call <botuser> is queued for destruction. On the second call, which must be in the form 'user confirm destroy <botuser>', the botuser will be destroyed. If you want to cancel the destruction, issue the command 'user cancel destroy <botuser>'") % {:highlight => Bold}
      else
        return _("user topics: show, enable|disable, add|rm netmask, set, reset, tell, create, list, destroy")
      end
    when "auth"
      return _("auth <masterpassword>: log in as the bot owner; other commands: login, whoami, permission syntax, permissions [re]set, permissions view, user, meet, hello")
    when "meet"
      return _("meet <nick> [as <user>]: creates a bot user for nick, calling it user (defaults to the nick itself)")
    when "hello"
      return _("hello: creates a bot user for the person issuing the command")
    else
      return _("auth commands: auth, login, whoami, who, permission[s], user, meet, hello")
    end
  end

  def need_args(cmd)
    _("sorry, I need more arguments to %{command}") % {:command => cmd}
  end

  def not_args(cmd, *stuff)
    _("I can only %{command} these: %{arguments}") %
      {:command => cmd, :arguments => stuff.join(', ')}
  end

  def set_prop(botuser, prop, val)
    k = prop.to_s.gsub("-","_")
    botuser.send( (k + "=").to_sym, val)
    if prop == :password and botuser == @bot.auth.botowner
      @bot.config.items[:'auth.password'].set_string(@bot.auth.botowner.password)
    end
  end

  def reset_prop(botuser, prop)
    k = prop.to_s.gsub("-","_")
    botuser.send( ("reset_"+k).to_sym)
  end

  def ask_bool_prop(botuser, prop)
    k = prop.to_s.gsub("-","_")
    botuser.send( (k + "?").to_sym)
  end

  def auth_manage_user(m, params)
    splits = params[:data]

    cmd = splits.first
    return auth_whoami(m, params) if cmd.nil?

    botuser = get_botuser_for(m.source)
    # By default, we do stuff on the botuser the irc user is bound to
    butarget = botuser

    has_for = splits[-2] == "for"
    if has_for
      butarget = @bot.auth.get_botuser(splits[-1]) rescue nil
      return m.reply(_("no such bot user %{user}") % {:user => splits[-1]}) unless butarget
      splits.slice!(-2,2)
    end
    return m.reply(_("you can't mess with %{user}") % {:user => butarget.username}) if butarget.owner? && botuser != butarget

    bools = [:autologin, :"login-by-mask"]
    can_set = [:password]
    can_addrm = [:netmasks]
    can_reset = bools + can_set + can_addrm
    can_show = can_reset + ["perms"]

    begin
    case cmd.to_sym

    when :show
      return m.reply(_("you can't see the properties of %{user}") %
             {:user => butarget.username}) if botuser != butarget &&
                                               !botuser.permit?("auth::show::other")

      case splits[1]
      when nil, "all"
        props = can_reset
      when "password"
        if botuser != butarget
          return m.reply(_("no way I'm telling you the master password!")) if butarget == @bot.auth.botowner
          return m.reply(_("you can't ask for someone else's password"))
        end
        return m.reply(_("c'mon, you can't be asking me seriously to tell you the password in public!")) if m.public?
        return m.reply(_("the password for %{user} is %{password}") %
          { :user => butarget.username, :password => butarget.password })
      else
        props = splits[1..-1]
      end

      str = []

      props.each { |arg|
        k = arg.to_sym
        next if k == :password
        case k
        when *bools
          if ask_bool_prop(butarget, k)
            str << _("can %{action}") % {:action => k}
          else
            str << _("can not %{action}") % {:action => k}
          end
        when :netmasks
          if butarget.netmasks.empty?
            str << _("knows no netmasks")
          else
            str << _("knows %{netmasks}") % {:netmasks => butarget.netmasks.join(", ")}
          end
        end
      }
      return m.reply("#{butarget.username} #{str.join('; ')}")

    when :enable, :disable
      return m.reply(_("you can't change the default user")) if butarget.default? && !botuser.permit?("auth::edit::other::default")
      return m.reply(_("you can't edit %{user}") % {:user => butarget.username}) if butarget != botuser && !botuser.permit?("auth::edit::other")

      return m.reply(need_args(cmd)) unless splits[1]
      things = []
      skipped = []
      splits[1..-1].each { |a|
        arg = a.to_sym
        if bools.include?(arg)
          set_prop(butarget, arg, cmd.to_sym == :enable)
          things << a
        else
          skipped << a
        end
      }

      m.reply(_("I ignored %{things} because %{reason}") % {
                :things => skipped.join(', '),
                :reason => not_args(cmd, *bools)}) unless skipped.empty?
      if things.empty?
        m.reply _("I haven't changed anything")
      else
        @bot.auth.set_changed
        return auth_manage_user(m, {:data => ["show"] + things + ["for", butarget.username] })
      end

    when :set
      return m.reply(_("you can't change the default user")) if
             butarget.default? && !botuser.permit?("auth::edit::default")
      return m.reply(_("you can't edit %{user}") % {:user=>butarget.username}) if
             butarget != botuser && !botuser.permit?("auth::edit::other")

      return m.reply(need_args(cmd)) unless splits[1]
      arg = splits[1].to_sym
      return m.reply(not_args(cmd, *can_set)) unless can_set.include?(arg)
      argarg = splits[2]
      return m.reply(need_args([cmd, splits[1]].join(" "))) unless argarg
      if arg == :password && m.public?
        return m.reply(_("is that a joke? setting the password in public?"))
      end
      set_prop(butarget, arg, argarg)
      @bot.auth.set_changed
      auth_manage_user(m, {:data => ["show", arg, "for", butarget.username] })

    when :reset
      return m.reply(_("you can't change the default user")) if
             butarget.default? && !botuser.permit?("auth::edit::default")
      return m.reply(_("you can't edit %{user}") % {:user=>butarget.username}) if
             butarget != botuser && !botuser.permit?("auth::edit::other")

      return m.reply(need_args(cmd)) unless splits[1]
      things = []
      skipped = []
      splits[1..-1].each { |a|
        arg = a.to_sym
        if can_reset.include?(arg)
          reset_prop(butarget, arg)
          things << a
        else
          skipped << a
        end
      }

      m.reply(_("I ignored %{things} because %{reason}") %
                { :things => skipped.join(', '),
                  :reason => not_args(cmd, *can_reset)}) unless skipped.empty?
      if things.empty?
        m.reply _("I haven't changed anything")
      else
        @bot.auth.set_changed
        @bot.say(m.source, _("the password for %{user} is now %{password}") %
          {:user => butarget.username, :password => butarget.password}) if
          things.include?("password")
        return auth_manage_user(m, {:data => (["show"] + things - ["password"]) + ["for", butarget.username]})
      end

    when :add, :rm, :remove, :del, :delete
      return m.reply(_("you can't change the default user")) if
             butarget.default? && !botuser.permit?("auth::edit::default")
      return m.reply(_("you can't edit %{user}") % {:user => butarget.username}) if
             butarget != botuser && !botuser.permit?("auth::edit::other")

      arg = splits[1]
      if arg.nil? or arg !~ /netmasks?/ or splits[2].nil?
        return m.reply(_("I can only add/remove netmasks. See +help user add+ for more instructions"))
      end

      method = cmd.to_sym == :add ? :add_netmask : :delete_netmask

      failed = []

      splits[2..-1].each { |mask|
        begin
          butarget.send(method, mask.to_irc_netmask(:server => @bot.server))
        rescue => e
          debug "failed with #{e.message}"
          debug e.backtrace.join("\n")
          failed << mask
        end
      }
      m.reply "I failed to #{cmd} #{failed.join(', ')}" unless failed.empty?
      @bot.auth.set_changed
      return auth_manage_user(m, {:data => ["show", "netmasks", "for", butarget.username] })

    else
      m.reply _("sorry, I don't know how to %{request}") % {:request => m.message}
    end
    rescue => e
      m.reply _("couldn't %{cmd}: %{exception}") % {:cmd => cmd, :exception => e}
    end
  end

  def auth_meet(m, params)
    nick = params[:nick]
    if !nick
      # we are actually responding to a 'hello' command
      unless m.botuser.transient?
        m.reply @bot.lang.get('hello_X') % m.botuser
        return
      end
      nick = m.sourcenick
      irc_user = m.source
    else
      # m.channel is always an Irc::Channel because the command is either
      # public-only 'meet' or private/public 'hello' which was handled by
      # the !nick case, so this shouldn't fail
      irc_user = m.channel.users[nick]
      return m.reply("I don't see anyone named '#{nick}' here") unless irc_user
    end
    # BotUser name
    buname = params[:user] || nick
    begin
      call_event(:botuser,:pre_perm, {:irc_user => irc_user, :bot_user => buname})
      met = @bot.auth.make_permanent(irc_user, buname)
      @bot.auth.set_changed
      call_event(:botuser,:post_perm, {:irc_user => irc_user, :bot_user => buname})
      m.reply @bot.lang.get('hello_X') % met
      @bot.say nick, _("you are now registered as %{buname}. I created a random password for you : %{pass} and you can change it at any time by telling me 'user set password <password>' in private" % {
        :buname => buname,
        :pass => met.password
      })
    rescue RuntimeError
      # or can this happen for other cases too?
      # TODO autologin if forced
      m.reply _("but I already know %{buname}" % {:buname => buname})
    rescue => e
      m.reply _("I had problems meeting %{nick}: %{e}" % { :nick => nick, :e => e })
    end
  end

  def auth_tell_password(m, params)
    user = params[:user]
    begin
      botuser = @bot.auth.get_botuser(params[:botuser])
    rescue
      return m.reply(_("couldn't find botuser %{user}") % {:user => params[:botuser]})
    end
    m.reply(_("I'm not telling the master password to anyway, pal")) if botuser == @bot.auth.botowner
    msg = _("the password for botuser %{user} is %{password}") %
          {:user => botuser.username, :password => botuser.password}
    @bot.say user, msg
    @bot.say m.source, _("I told %{user} that %{message}") % {:user => user, :message => msg}
  end

  def auth_create_user(m, params)
    name = params[:name]
    password = params[:password]
    return m.reply(_("are you nuts, creating a botuser with a publicly known password?")) if m.public? and not password.nil?
    begin
      bu = @bot.auth.create_botuser(name, password)
      @bot.auth.set_changed
    rescue => e
      m.reply(_("failed to create %{user}: %{exception}") % {:user => name,  :exception => e})
      debug e.inspect + "\n" + e.backtrace.join("\n")
      return
    end
    m.reply(_("created botuser %{user}") % {:user => bu.username})
  end

  def auth_list_users(m, params)
    # TODO name regexp to filter results
    list = @bot.auth.save_array.inject([]) { |list, x| ['everyone', 'owner'].include?(x[:username]) ? list : list << x[:username] }
    if defined?(@destroy_q)
      list.map! { |x|
        @destroy_q.include?(x) ? x + _(" (queued for destruction)") : x
      }
    end
    return m.reply(_("I have no botusers other than the default ones")) if list.empty?
    return m.reply(n_("botuser: %{list}", "botusers: %{list}", list.length) %
                   {:list => list.join(', ')})
  end

  def auth_destroy_user(m, params)
    @destroy_q = [] unless defined?(@destroy_q)
    buname = params[:name]
    return m.reply(_("You can't destroy %{user}") % {:user => buname}) if
           ["everyone", "owner"].include?(buname)
    mod = params[:modifier].to_sym rescue nil

    buser_array = @bot.auth.save_array
    buser_hash = buser_array.inject({}) { |h, u|
      h[u[:username]] = u
      h
    }

    return m.reply(_("no such botuser %{user}") % {:user=>buname}) unless
           buser_hash.keys.include?(buname)

    case mod
    when :cancel
      if @destroy_q.include?(buname)
        @destroy_q.delete(buname)
        m.reply(_("%{user} removed from the destruction queue") % {:user=>buname})
      else
        m.reply(_("%{user} was not queued for destruction") % {:user=>buname})
      end
      return
    when nil
      if @destroy_q.include?(buname)
        return m.reply(_("%{user} already queued for destruction, use %{highlight}user confirm destroy %{user}%{highlight} to destroy it") % {:user=>buname, :highlight=>Bold})
      else
        @destroy_q << buname
        return m.reply(_("%{user} queued for destruction, use %{highlight}user confirm destroy %{user}%{highlight} to destroy it") % {:user=>buname, :highlight=>Bold})
      end
    when :confirm
      begin
        return m.reply(_("%{user} is not queued for destruction yet") %
               {:user=>buname}) unless @destroy_q.include?(buname)
        buser_array.delete_if { |u|
          u[:username] == buname
        }
        @destroy_q.delete(buname)
        @bot.auth.load_array(buser_array, true)
        @bot.auth.set_changed
      rescue => e
        return m.reply(_("failed: %{exception}") % {:exception => e})
      end
      return m.reply(_("botuser %{user} destroyed") % {:user => buname})
    end
  end

  def auth_copy_ren_user(m, params)
    source = Auth::BotUser.sanitize_username(params[:source])
    dest = Auth::BotUser.sanitize_username(params[:dest])
    return m.reply(_("please don't touch the default users")) unless
      (["everyone", "owner"] & [source, dest]).empty?

    buser_array = @bot.auth.save_array
    buser_hash = buser_array.inject({}) { |h, u|
      h[u[:username]] = u
      h
    }

    return m.reply(_("no such botuser %{source}") % {:source=>source}) unless
           buser_hash.keys.include?(source)
    return m.reply(_("botuser %{dest} exists already") % {:dest=>dest}) if
           buser_hash.keys.include?(dest)

    copying = m.message.split[1] == "copy"
    begin
      if copying
        h = {}
        buser_hash[source].each { |k, val|
          h[k] = val.dup
        }
      else
        h = buser_hash[source]
      end
      h[:username] = dest
      buser_array << h if copying

      @bot.auth.load_array(buser_array, true)
      @bot.auth.set_changed
      call_event(:botuser, copying ? :copy : :rename, :source => source, :dest => dest)
    rescue => e
      return m.reply(_("failed: %{exception}") % {:exception=>e})
    end
    if copying
      m.reply(_("botuser %{source} copied to %{dest}") %
           {:source=>source, :dest=>dest})
    else
      m.reply(_("botuser %{source} renamed to %{dest}") %
           {:source=>source, :dest=>dest})
    end

  end

  def auth_export(m, params)

    exportfile = "#{@bot.botclass}/new-auth.users"

    what = params[:things]

    has_to = what[-2] == "to"
    if has_to
      exportfile = "#{@bot.botclass}/#{what[-1]}"
      what.slice!(-2,2)
    end

    what.delete("all")

    m.reply _("selecting data to export ...")

    buser_array = @bot.auth.save_array
    buser_hash = buser_array.inject({}) { |h, u|
      h[u[:username]] = u
      h
    }

    if what.empty?
      we_want = buser_hash
    else
      we_want = buser_hash.delete_if { |key, val|
        not what.include?(key)
      }
    end

    m.reply _("preparing data for export ...")
    begin
      yaml_hash = {}
      we_want.each { |k, val|
        yaml_hash[k] = {}
        val.each { |kk, v|
          case kk
          when :username
            next
          when :netmasks
            yaml_hash[k][kk] = []
            v.each { |nm|
              yaml_hash[k][kk] << {
                :fullform => nm.fullform,
                :casemap => nm.casemap.to_s
              }
            }
          else
            yaml_hash[k][kk] = v
          end
        }
      }
    rescue => e
      m.reply _("failed to prepare data: %{exception}") % {:exception=>e}
      debug e.backtrace.dup.unshift(e.inspect).join("\n")
      return
    end

    m.reply _("exporting to %{file} ...") % {:file=>exportfile}
    begin
      # m.reply yaml_hash.inspect
      File.open(exportfile, "w") do |file|
        file.puts YAML::dump(yaml_hash)
      end
    rescue => e
      m.reply _("failed to export users: %{exception}") % {:exception=>e}
      debug e.backtrace.dup.unshift(e.inspect).join("\n")
      return
    end
    m.reply _("done")
  end

  def auth_import(m, params)

    importfile = "#{@bot.botclass}/new-auth.users"

    what = params[:things]

    has_from = what[-2] == "from"
    if has_from
      importfile = "#{@bot.botclass}/#{what[-1]}"
      what.slice!(-2,2)
    end

    what.delete("all")

    m.reply _("reading %{file} ...") % {:file=>importfile}
    begin
      yaml_hash = YAML::load_file(importfile)
    rescue => e
      m.reply _("failed to import from: %{exception}") % {:exception=>e}
      debug e.backtrace.dup.unshift(e.inspect).join("\n")
      return
    end

    # m.reply yaml_hash.inspect

    m.reply _("selecting data to import ...")

    if what.empty?
      we_want = yaml_hash
    else
      we_want = yaml_hash.delete_if { |key, val|
        not what.include?(key)
      }
    end

    m.reply _("parsing data from import ...")

    buser_hash = {}

    begin
      yaml_hash.each { |k, val|
        buser_hash[k] = { :username => k }
        val.each { |kk, v|
          case kk
          when :netmasks
            buser_hash[k][kk] = []
            v.each { |nm|
              buser_hash[k][kk] << nm[:fullform].to_irc_netmask(:casemap => nm[:casemap].to_irc_casemap).to_irc_netmask(:server => @bot.server)
            }
          else
            buser_hash[k][kk] = v
          end
        }
      }
    rescue => e
      m.reply _("failed to parse data: %{exception}") % {:exception=>e}
      debug e.backtrace.dup.unshift(e.inspect).join("\n")
      return
    end

    # m.reply buser_hash.inspect

    org_buser_array = @bot.auth.save_array
    org_buser_hash = org_buser_array.inject({}) { |h, u|
      h[u[:username]] = u
      h
    }

    # TODO we may want to do a(n optional) key-by-key merge
    #
    org_buser_hash.merge!(buser_hash)
    new_buser_array = org_buser_hash.values
    @bot.auth.load_array(new_buser_array, true)
    @bot.auth.set_changed

    m.reply _("done")
  end

end

auth = AuthModule.new

auth.map "user export *things",
  :action => 'auth_export',
  :defaults => { :things => ['all'] },
  :auth_path => ':manage:fedex:'

auth.map "user import *things",
 :action => 'auth_import',
 :auth_path => ':manage:fedex:'

auth.map "user create :name :password",
  :action => 'auth_create_user',
  :defaults => {:password => nil},
  :auth_path => ':manage:'

auth.map "user [:modifier] destroy :name",
  :action => 'auth_destroy_user',
  :requirements => { :modifier => /^(cancel|confirm)?$/ },
  :defaults => { :modifier => '' },
  :auth_path => ':manage::destroy!'

auth.map "user copy :source [to] :dest",
  :action => 'auth_copy_ren_user',
  :auth_path => ':manage:'

auth.map "user rename :source [to] :dest",
  :action => 'auth_copy_ren_user',
  :auth_path => ':manage:'

auth.map "meet :nick [as :user]",
  :action => 'auth_meet',
  :auth_path => 'user::manage', :private => false

auth.map "hello",
  :action => 'auth_meet',
  :auth_path => 'user::manage::meet'

auth.default_auth("user::manage", false)
auth.default_auth("user::manage::meet::hello", true)

auth.map "user tell :user the password for :botuser",
  :action => 'auth_tell_password',
  :auth_path => '::'

auth.map "user list",
  :action => 'auth_list_users',
  :auth_path => '::'

auth.map "user *data",
  :action => 'auth_manage_user'

auth.default_auth("user", true)
auth.default_auth("edit::other", false)

auth.map "whoami",
  :action => 'auth_whoami',
  :auth_path => '!*!'

auth.map "who is :user",
  :action => 'auth_whois',
  :auth_path => '!*!'

auth.map "auth :password",
  :action => 'auth_auth',
  :public => false,
  :auth_path => '!login!'

auth.map "login :botuser :password",
  :action => 'auth_login',
  :public => false,
  :defaults => { :password => nil },
  :auth_path => '!login!'

auth.map "login :botuser",
  :action => 'auth_login',
  :auth_path => '!login!'

auth.map "login",
  :action => 'auth_autologin',
  :auth_path => '!login!'

auth.map "permissions set *args",
  :action => 'auth_edit_perm',
  :auth_path => ':edit::set:'

auth.map "permissions reset *args",
  :action => 'auth_edit_perm',
  :auth_path => ':edit::reset:'

auth.map "permissions view [for :user]",
  :action => 'auth_view_perm',
  :auth_path => '::'

auth.default_auth('*', false)

