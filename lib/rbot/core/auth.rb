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

  def auth_login(m, params)
    begin
      case @bot.auth.login(m.source, params[:botuser], params[:password])
      when true
        m.reply "welcome, #{@bot.auth.irc_to_botuser(m.source).username}"
        @bot.auth.set_changed
      else
        m.reply "sorry, can't do"
      end
    rescue => e
      m.reply "couldn't login: #{e}"
      raise
    end
  end

end

auth = AuthModule.new

auth.map "permissions set *args for :user",
  :action => 'auth_set',
  :auth_path => ':edit::set:'

auth.map "permissions reset *args for :user",
  :action => 'auth_reset',
  :auth_path => ':edit::reset:'

auth.map "login :botuser :password",
  :action => 'auth_login',
  :public => false,
  :defaults => { :password => nil },
  :auth_path => '!login!'

auth.map "login :botuser",
  :action => 'auth_login',
  :defaults => { :password => nil },
  :auth_path => '!login!'

auth.default_auth('*', false)

