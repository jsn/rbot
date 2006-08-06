#-- vim:sw=2:et
#++
# TODO:
# * user destroy: should work in two phases:
#   * <code>user destroy _botuser_</code> would queue _botuser_ for
#     destruction
#   * <code>user destroy _botuser_ _password_</code> would actually destroy
#     _botuser_ if it was queued and the _password_ is correct
# * user copy
# * user rename
#
# It should be fairly easy to implement all of this stuff by using
# @bot.auth.load_array and @bot.auth.save_array: this means it can be tested
# live and without any need to touch the rbot kernel file +botuser.rb+
#


class AuthModule < CoreBotModule

  def initialize
    super
    load_array(:default, true)
    debug "Initialized auth. Botusers: #{@bot.auth.save_array.inspect}"
  end

  def save
    save_array
  end

  def save_array(key=:default)
    if @bot.auth.changed?
      @registry[key] = @bot.auth.save_array
      @bot.auth.reset_changed
      debug "saved botusers (#{key}): #{@registry[key].inspect}"
    end
  end

  def load_array(key=:default, forced=false)
    debug "loading botusers (#{key}): #{@registry[key].inspect}"
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
          warns << ArgumentError("please do not use + or - in front of command #{x} when resetting") unless setting
        else
          warns << ArgumentError("+ or - expected in front of #{x}") if setting
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
          warns << ArgumentError("#{x} doesn't look like a channel name") unless @bot.server.supports[:chantypes].include?(x[0])
          locs << x
        end
        unless wants_more
          last_idx = i
          break
        end
      end
    }
    warns << "trailing comma" if wants_more
    warns << "you probably forgot a comma" unless last_idx == ar.length - 1
    return cmds, locs, warns
  end

  def auth_set(m, params)
    cmds, locs, warns = parse_args(params[:args])
    errs = warns.select { |w| w.kind_of?(Exception) }
    unless errs.empty?
      m.reply "couldn't satisfy your request: #{errs.join(',')}"
      return
    end
    user = params[:user].sub(/^all$/,"everyone")
    begin
      bu = @bot.auth.get_botuser(user)
    rescue
      return m.reply "couldn't find botuser #{user}"
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
          val = setval[0].chr == '+'
          cmd = setval[1..-1]
          bu.set_permission(cmd, val, ch)
        }
      }
    rescue => e
      m.reply "Something went wrong while trying to set the permissions"
      raise
    end
    @bot.auth.set_changed
    debug "User #{user} permissions changed"
    m.reply "Ok, #{user} now also has permissions #{params[:args].join(' ')}"
  end

  def get_botuser_for(user)
    @bot.auth.irc_to_botuser(user)
  end

  def get_botusername_for(user)
    get_botuser_for(user).username
  end

  def welcome(user)
    "welcome, #{get_botusername_for(user)}"
  end

  def auth_login(m, params)
    begin
      case @bot.auth.login(m.source, params[:botuser], params[:password])
      when true
        m.reply welcome(m.source)
        @bot.auth.set_changed
      else
        m.reply "sorry, can't do"
      end
    rescue => e
      m.reply "couldn't login: #{e}"
      raise
    end
  end

  def auth_autologin(m, params)
    u = do_autologin(m.source)
    case u.username
    when 'everyone'
      m.reply "I couldn't find anything to let you login automatically"
    else
      m.reply welcome(m.source)
    end
  end

  def do_autologin(user)
    @bot.auth.autologin(user)
  end

  def auth_whoami(m, params)
    rep = ""
    # if m.public?
    #   rep << m.source.nick << ", "
    # end
    rep << "you are "
    rep << get_botusername_for(m.source).gsub(/^everyone$/, "no one that I know").gsub(/^owner$/, "my boss")
    m.reply rep
  end

  def help(plugin, topic="")
    case topic
    when /^login/
      return "login [<botuser>] [<pass>]: logs in to the bot as botuser <botuser> with password <pass>. <pass> can be omitted if <botuser> allows login-by-mask and your netmask is among the known ones. if <botuser> is omitted too autologin will be attempted"
    when /^whoami/
      return "whoami: names the botuser you're linked to"
    when /^permission syntax/
      return "A permission is specified as module::path::to::cmd; when you want to enable it, prefix it with +; when you want to disable it, prefix it with -; when using the +reset+ command, do not use any prefix"
    when /^permission/
      return "permissions (re)set <permission> [in <channel>] for <user>: sets or resets the permissions for botuser <user> in channel <channel> (use ? to change the permissions for private addressing)"
    when /^user show/
      return "user show <what> : shows info about the user; <what> can be any of autologin, login-by-mask, netmasks"
    when /^user (en|dis)able/
      return "user enable|disable <what> : turns on or off <what> (autologin, login-by-mask)"
    when /^user set/
      return "user set password <blah> : sets the user password to <blah>; passwords can only contain upper and lowercase letters and numbers, and must be at least 4 characters long"
    when /^user (add|rm)/
      return "user add|rm netmask <mask> : adds/removes netmask <mask> from the list of netmasks known to the botuser you're linked to"
    when /^user reset/
      return "user reset <what> : resets <what> to the default values. <what> can be +netmasks+ (the list will be emptied), +autologin+ or +login-by-mask+ (will be reset to the default value) or +password+ (a new one will be generated and you'll be told in private)"
    when /^user tell/
      return "user tell <who> the password for <botuser> : contacts <who> in private to tell him/her the password for <botuser>"
    when /^user create/
      return "user create <name> <password> : create botuser named <name> with password <password>. The password can be omitted, in which case a random one will be generated. The <name> should only contain alphanumeric characters and the underscore (_)"
    when /^user list/
      return "user list : lists all the botusers"
    when /^user destroy/
      return "user destroy <botuser> <password> : destroys <botuser>; this function #{Bold}must#{Bold} be called in two steps. On the first call, no password must be specified: <botuser> is then queued for destruction. On the second call, you must specify the correct password for <botuser>, and it will be destroyed. If you want to cancel the destruction, issue the command +user cancel destroy <botuser>+"
    when /^user/
      return "user show, enable|disable, add|rm netmask, set, reset, tell, create, list, destroy"
    else
      return "#{name}: login, whoami, permission syntax, permissions, user"
    end
  end

  def need_args(cmd)
    "sorry, I need more arguments to #{cmd}"
  end

  def not_args(cmd, *stuff)
    "I can only #{cmd} these: #{stuff.join(', ')}"
  end

  def set_prop(botuser, prop, val)
    k = prop.to_s.gsub("-","_")
    botuser.send( (k + "=").to_sym, val)
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
    butarget = @bot.auth.get_botuser(splits[-1]) if has_for
    return m.reply "you can't mess with #{butarget.username}" if butarget == @bot.auth.botowner && botuser != butarget
    splits.slice!(-2,2) if has_for

    bools = [:autologin, :"login-by-mask"]
    can_set = [:password]
    can_addrm = [:netmasks]
    can_reset = bools + can_set + can_addrm

    case cmd.to_sym

    when :show
      return "you can't see the properties of #{butarget.username}" if botuser != butarget and !botuser.permit?("auth::show::other")

      case splits[1]
      when nil, "all"
        props = can_reset
      when "password"
        if botuser != butarget
          return m.reply "no way I'm telling you the master password!" if butarget == @bot.auth.botowner
          return m.reply "you can't ask for someone else's password"
        end
        return m.reply "c'mon, you can't be asking me seriously to tell you the password in public!" if m.public?
        return m.reply "the password for #{butarget.username} is #{butarget.password}"
      else
        props = splits[1..-1]
      end

      str = []

      props.each { |arg|
        k = arg.to_sym
        next if k == :password
        case k
        when *bools
          str << "can"
          str.last << "not" unless ask_bool_prop(butarget, k)
          str.last << " #{k}"
        when :netmasks
          str << "knows "
          if butarget.netmasks.empty?
            str.last << "no netmasks"
          else
            str.last << butarget.netmasks.join(", ")
          end
        end
      }
      return m.reply "#{butarget.username} #{str.join('; ')}"

    when :enable, :disable
      return m.reply "you can't change the default user" if butarget == @bot.auth.everyone and !botuser.permit?("auth::edit::other::default")
      return m.reply "you can't edit #{butarget.username}" if butarget != botuser and !botuser.permit?("auth::edit::other")

      return m.reply need_args(cmd) unless splits[1]
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

      m.reply "I ignored #{skipped.join(', ')} because " + not_args(cmd, *bools) unless skipped.empty?
      if things.empty?
        m.reply "I haven't changed anything"
      else
        @bot.auth.set_changed
        return auth_manage_user(m, {:data => ["show"] + things })
      end

    when :set
      return m.reply "you can't change the default user" if butarget == @bot.auth.everyone and !botuser.permit?("auth::edit::default")
      return m.reply "you can't edit #{butarget.username}" if butarget != botuser and !botuser.permit?("auth::edit::other")

      return m.reply need_args(cmd) unless splits[1]
      arg = splits[1].to_sym
      return m.reply not_args(cmd, *can_set) unless can_set.include?(arg)
      argarg = splits[2]
      return m.reply need_args([cmd, splits[1]].join(" ")) unless argarg
      if arg == :password && m.public?
        return m.reply "is that a joke? setting the password in public?"
      end
      set_prop(butarget, arg, argarg)
      @bot.auth.set_changed
      auth_manage_user(m, {:data => ["show", arg] })

    when :reset
      return m.reply "you can't change the default user" if butarget == @bot.auth.everyone and !botuser.permit?("auth::edit::default")
      return m.reply "you can't edit #{butarget.username}" if butarget != botuser and !botuser.permit?("auth::edit::other")

      return m.reply need_args(cmd) unless splits[1]
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

      m.reply "I ignored #{skipped.join(', ')} because " + not_args(cmd, *can_reset) unless skipped.empty?
      if things.empty?
        m.reply "I haven't changed anything"
      else
        @bot.auth.set_changed
        @bot.say m.source, "the password for #{butarget.username} is now #{butarget.password}" if things.include?("password")
        return auth_manage_user(m, {:data => ["show"] + things - ["password"]})
      end

    when :add, :rm, :remove, :del, :delete
      return m.reply "you can't change the default user" if butarget == @bot.auth.everyone and !botuser.permit?("auth::edit::default")
      return m.reply "you can't edit #{butarget.username}" if butarget != botuser and !botuser.permit?("auth::edit::other")

      arg = splits[1]
      if arg.nil? or arg !~ /netmasks?/ or splits[2].nil?
        return m.reply "I can only add/remove netmasks. See +help user add+ for more instructions"
      end

      method = cmd.to_sym == :add ? :add_netmask : :delete_netmask

      failed = []

      splits[2..-1].each { |mask|
        begin
          butarget.send(method, mask.to_irc_netmask(:server => @bot.server))
        rescue
          failed << mask
        end
      }
      m.reply "I failed to #{cmd} #{failed.join(', ')}" unless failed.empty?
      @bot.auth.set_changed
      return auth_manage_user(m, {:data => ["show", "netmasks"] })

    else
      m.reply "sorry, I don't know how to #{m.message}"
    end
  end

  def auth_tell_password(m, params)
    user = params[:user]
    begin
      botuser = @bot.auth.get_botuser(params[:botuser])
    rescue
      return m.reply "coudln't find botuser #{params[:botuser]})"
    end
    m.reply "I'm not telling the master password to anyway, pal" if botuser == @bot.auth.botowner
    msg = "the password for botuser #{botuser.username} is #{botuser.password}"
    @bot.say user, msg
    @bot.say m.source, "I told #{user} that " + msg
  end

  def auth_create_user(m, params)
    name = params[:name]
    password = params[:password]
    return m.reply "are you nuts, creating a botuser with a publicly known password?" if m.public? and not password.nil?
    begin
      bu = @bot.auth.create_botuser(name, password)
      @bot.auth.set_changed
    rescue => e
      return m.reply "Failed to create #{name}: #{e}"
      debug e.inspect + "\n" + e.backtrace.join("\n")
    end
    m.reply "Created botuser #{bu.username}"
  end

  def auth_list_users(m, params)
    # TODO name regexp to filter results
    list = @bot.auth.save_array.inject([]) { |list, x| list << x[:username] } - ['everyone', 'owner']
    if defined?(@destroy_q)
      list.map! { |x|
        @destroy_q.include?(x) ? x + " (queued for destruction)" : x
      }
    end
    return m.reply "I have no botusers other than the default ones" if list.empty?
    return m.reply "Botuser#{'s' if list.length > 1}: #{list.join(', ')}"
  end

  def auth_destroy_user(m, params)
    @destroy_q = [] unless defined?(@destroy_q)
    buname = params[:name]
    returm m.reply "You can't destroy #{buname}" if ["everyone", "owner"].include?(buname)
    cancel = m.message.split[1] == 'cancel'
    password = params[:password]
    buser_array = @bot.auth.save_array
    buser_hash = buser_array.inject({}) { |h, u|
      h[u[:username]] = u
      h
    }

    return m.reply "No such botuser #{buname}" unless buser_hash.keys.include?(buname)

    if cancel
      if @destroy_q.include?(buname)
        @destroy_q.delete(buname)
        m.reply "#{buname} removed from the destruction queue"
      else
        m.reply "#{buname} was not queued for destruction"
      end
      return
    end

    if password.nil?
      if @destroy_q.include?(buname)
        rep = "#{buname} already queued for destruction"
      else
        @destroy_q << buname
        rep = "#{buname} queued for destruction"
      end
      return m.reply rep + ", use #{Bold}user destroy #{buname} <password>#{Bold} to destroy it"
    else
      begin
        return m.reply "#{buname} is not queued for destruction yet" unless @destroy_q.include?(buname)
        return m.reply "wrong password for #{buname}" unless buser_hash[buname][:password] == password
        buser_array.delete_if { |u|
          u[:username] == buname
        }
        @destroy_q.delete(buname)
        @bot.auth.load_array(buser_array, true)
      rescue => e
        return m.reply "failed: #{e}"
      end
      return m.reply "user #{buname} destroyed"
    end

  end

end

auth = AuthModule.new

auth.map "user create :name :password",
  :action => 'auth_create_user',
  :defaults => {:password => nil},
  :auth_path => 'user::manage::create!'

auth.map "user cancel destroy :name :password",
  :action => 'auth_destroy_user',
  :defaults => { :password => nil },
  :auth_path => 'user::manage::destroy::cancel!'

auth.map "user destroy :name :password",
  :action => 'auth_destroy_user',
  :defaults => { :password => nil },
  :auth_path => 'user::manage::destroy!'

auth.default_auth("user::manage", false)

auth.map "user tell :user the password for :botuser",
  :action => 'auth_tell_password',
  :auth_path => 'user::tell'

auth.map "user list",
  :action => 'auth_list_users',
  :auth_path => 'user::list!'

auth.map "user *data",
  :action => 'auth_manage_user'

auth.default_auth("user", true)
auth.default_auth("edit::other", false)

auth.map "whoami",
  :action => 'auth_whoami',
  :auth_path => '!*!'

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

auth.map "permissions set *args for :user",
  :action => 'auth_set',
  :auth_path => ':edit::set:'

auth.map "permissions reset *args for :user",
  :action => 'auth_reset',
  :auth_path => ':edit::reset:'

auth.default_auth('*', false)

