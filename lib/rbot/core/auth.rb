#-- vim:sw=2:et
#++


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
      m.reply "couldn't find botuser #{user}"
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
    else
      return "#{name}: login, whoami, permission syntax, permissions"
    end
  end

  def need_args(cmd)
    "sorry, I need more arguments to #{cmd}"
  end

  def not_args(cmd, *stuff)
    "I can only #{cmd} these: #{stuff.join(', ')}"
  end

  def set_bool_prop(botuser, prop, val)
    k = prop.to_s.gsub("-","_")
    botuser.send( (k + "=").to_sym, val)
  end

  def reset_bool_prop(botuser, prop)
    k = prop.to_s.gsub("-","_")
    botuser.send( (k + "=").to_sym, @bot.config['auth.' + k])
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
    can_set = [:password] + bools
    can_reset = can_set + [:netmasks]

    case cmd.to_sym

    when :show, :list
      return "you can't see the properties of #{butarget.username}" if botuser != butarget and !botuser.permit?("auth::show::other")

      case splits[1]
      when nil, "all"
        props = can_reset
      when "password"
        return m.reply "you can't ask for someone else's password" if botuser != butarget and !botuser.permit?("auth::show::other::password")
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
      return m.reply "you can't change the default user" if butarget == @bot.auth.everyone and !botuser.permit?("auth::edit::default")
      return m.reply "you can't edit #{butarget.username}" if butarget != botuser and !botuser.permit?("auth::edit::other")

      return m.reply need_args(cmd) unless splits[1]
      things = []
      splits[1..-1].each { |a|
        arg = a.to_sym
        if  bools.include?(arg)
          set_bool_prop(butarget, arg, cmd.to_sym == :enable)
        else
          m.reply not_args(cmd, *bools)
        end
        things << a
      }
      return auth_manage_user(m, {:data => ["show"] + things })

    when :set
      return m.reply "you can't change the default user" if butarget == @bot.auth.everyone and !botuser.permit?("auth::edit::default")
      return m.reply "you can't edit #{butarget.username}" if butarget != botuser and !botuser.permit?("auth::edit::other")

      return need_args(cmd) unless splits[1]
      things = []
      # TODO
      #return not_args(cmd, *can_set) unless bools.include?(arg)

    when :reset
      return m.reply "you can't change the default user" if butarget == @bot.auth.everyone and !botuser.permit?("auth::edit::default")
      return m.reply "you can't edit #{butarget.username}" if butarget != botuser and !botuser.permit?("auth::edit::other")

      return need_args(cmd) unless splits[1]
      things = []
      # TODO
    else
      m.reply "sorry, I don't know how to #{m.message}"
    end
  end

end

auth = AuthModule.new

auth.map "user *data",
  :action => 'auth_manage_user'

auth.default_auth("user", true)

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

