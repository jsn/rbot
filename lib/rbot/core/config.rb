#-- vim:sw=2:et
#++
#
# :title: rbot config management from IRC
#
# Author:: Giuseppe "Oblomov" Bilotta <giuseppe.bilotta@gmail.com>
# Copyright:: (C) 2006,2007 Giuseppe Bilotta
# License:: GPL v2

class ConfigModule < CoreBotModule

  def version_string
    _("I'm a v. %{version} rubybot%{copyright}%{url}") % {
      :version => $version,
      :copyright => ", #{Irc::Bot::COPYRIGHT_NOTICE}",
      :url => " - #{Irc::Bot::SOURCE_URL}"
    }
  end

  def save
    @bot.config.save
  end

  def handle_list(m, params)
    modules = []
    if params[:module]
      @bot.config.items.each_key do |key|
        mod, name = key.to_s.split('.')
        next unless mod == params[:module]
        modules.push key unless modules.include?(name)
      end
      if modules.empty?
        m.reply _("no such module %{module}") % {:module => params[:module]}
      else
        m.reply modules.join(", ")
      end
    else
      @bot.config.items.each_key do |key|
        name = key.to_s.split('.').first
        modules.push name unless modules.include?(name)
      end
      m.reply "modules: " + modules.join(", ")
    end
  end

  def handle_get(m, params)
    key = params[:key].to_s.intern
    unless @bot.config.items.has_key?(key)
      m.reply _("no such config key %{key}") % {:key => key}
      return
    end
    return if !@bot.auth.allow?(@bot.config.items[key].auth_path, m.source, m.replyto)
    value = @bot.config.items[key].to_s
    m.reply "#{key}: #{value}"
  end

  def handle_desc(m, params)
    key = params[:key].to_s.intern
    unless @bot.config.items.has_key?(key)
      m.reply _("no such config key %{key}") % {:key => key}
    end
    m.reply "#{key}: #{@bot.config.items[key].desc}"
  end

  def handle_unset(m, params)
    key = params[:key].to_s.intern
    unless @bot.config.items.has_key?(key)
      m.reply _("no such config key %{key}") % {:key => key}
    end
    return if !@bot.auth.allow?(@bot.config.items[key].auth_path, m.source, m.replyto)
    @bot.config.items[key].unset
    handle_get(m, params)
    m.reply _("this config change will take effect on the next restart") if @bot.config.items[key].requires_restart
    m.reply _("this config change will take effect on the next rescan") if @bot.config.items[key].requires_rescan
  end

  def handle_set(m, params)
    key = params[:key].to_s.intern
    value = params[:value].join(" ")
    unless @bot.config.items.has_key?(key)
      m.reply _("no such config key %{key}") % {:key => key} unless params[:silent]
      return false
    end
    return false if !@bot.auth.allow?(@bot.config.items[key].auth_path, m.source, m.replyto)
    begin
      @bot.config.items[key].set_string(value)
    rescue ArgumentError => e
      m.reply _("failed to set %{key}: %{error}") % {:key => key, :error => e.message} unless params[:silent]
      return false
    end
    if @bot.config.items[key].requires_restart
      m.reply _("this config change will take effect on the next restart") unless params[:silent]
      return :restart
    elsif @bot.config.items[key].requires_rescan
      m.reply _("this config change will take effect on the next rescan") unless params[:silent]
      return :rescan
    else
      m.okay unless params[:silent]
      return true
    end
  end

  def handle_add(m, params)
    key = params[:key].to_s.intern
    value = params[:value]
    unless @bot.config.items.has_key?(key)
      m.reply _("no such config key %{key}") % {:key => key}
      return
    end
    unless @bot.config.items[key].kind_of?(BotConfigArrayValue)
      m.reply _("config key %{key} is not an array") % {:key => key}
      return
    end
    return if !@bot.auth.allow?(@bot.config.items[key].auth_path, m.source, m.replyto)
    begin
      @bot.config.items[key].add(value)
    rescue ArgumentError => e
      m.reply _("failed to add %{value} to %{key}: %{error}") % {:value => value, :key => key, :error => e.message}
      return
    end
    handle_get(m,{:key => key})
    m.reply _("this config change will take effect on the next restart") if @bot.config.items[key].requires_restart
    m.reply _("this config change will take effect on the next rescan") if @bot.config.items[key].requires_rescan
  end

  def handle_rm(m, params)
    key = params[:key].to_s.intern
    value = params[:value]
    unless @bot.config.items.has_key?(key)
      m.reply _("no such config key %{key}") % {:key => key}
      return
    end
    unless @bot.config.items[key].kind_of?(BotConfigArrayValue)
      m.reply _("config key %{key} is not an array") % {:key => key}
      return
    end
    return if !@bot.auth.allow?(@bot.config.items[key].auth_path, m.source, m.replyto)
    begin
      @bot.config.items[key].rm(value)
    rescue ArgumentError => e
      m.reply _("failed to remove %{value} from %{key}: %{error}") % {:value => value, :key => key, :error => e.message}
      return
    end
    handle_get(m,{:key => key})
    m.reply _("this config change will take effect on the next restart") if @bot.config.items[key].requires_restart
    m.reply _("this config change will take effect on the next rescan") if @bot.config.items[key].requires_rescan
  end

  def bot_save(m, param)
    @bot.save
    m.okay
  end

  def bot_rescan(m, param)
    m.reply _("saving ...")
    @bot.save
    m.reply _("rescanning ...")
    @bot.rescan
    m.reply _("done. %{plugin_status}") % {:plugin_status => @bot.plugins.status(true)}
  end

  def bot_nick(m, param)
    @bot.nickchg(param[:nick])
  end

  def bot_status(m, param)
    m.reply @bot.status
  end

  # TODO is this one of the methods that disappeared when the bot was moved
  # from the single-file to the multi-file registry?
  #
  #  def bot_reg_stat(m, param)
  #    m.reply @registry.stat.inspect
  #  end

  def bot_version(m, param)
    m.reply version_string
  end

  def ctcp_listen(m)
    who = m.private? ? "me" : m.target
    case m.ctcp.intern
    when :VERSION
      m.ctcp_reply version_string
      @bot.irclog "@ #{m.source} asked #{who} about version info"
    when :SOURCE
      m.ctcp_reply Irc::Bot::SOURCE_URL
      @bot.irclog "@ #{m.source} asked #{who} about source info"
    end
  end

  def handle_help(m, params)
    m.reply help(params[:topic])
  end

  def help(plugin, topic="")
    case plugin
    when "config"
      case topic
      when ""
      _("config-related tasks: config topics, save, rescan")
      when "list"
      _("config list => list configuration modules, config list <module> => list configuration keys for module <module>")
      when "get"
      _("config get <key> => get configuration value for key <key>")
      when "unset"
      _("reset key <key> to the default")
      when "set"
      _("config set <key> <value> => set configuration value for key <key> to <value>")
      when "desc"
      _("config desc <key> => describe what key <key> configures")
      when "add"
      _("config add <value> to <key> => add value <value> to key <key> if <key> is an array")
      when "rm"
      _("config rm <value> from <key> => remove value <value> from key <key> if <key> is an array")
      else
      _("config module - bot configuration. usage: list, desc, get, set, unset, add, rm")
      # else
      #   "no help for config #{topic}"
      end
    when "save"
      _("save => save current dynamic data and configuration")
    when "rescan"
      _("rescan => reload modules and static facts")
    when "version"
      _("version => describes software version")
    else
      _("config-related tasks: config, save, rescan, version")
    end
  end

end

conf = ConfigModule.new

conf.map 'config list :module',
  :action => 'handle_list',
  :defaults => {:module => false},
  :auth_path => 'show'
# TODO this one is presently a security risk, since the bot
# stores the master password in the config. Do we need auth levels
# on the BotConfig keys too?
conf.map 'config get :key',
  :action => 'handle_get',
  :auth_path => 'show'
conf.map 'config desc :key',
  :action => 'handle_desc',
  :auth_path => 'show'
conf.map 'config describe :key',
  :action => 'handle_desc',
  :auth_path => 'show'

conf.map "save",
  :action => 'bot_save'
conf.map "rescan",
  :action => 'bot_rescan'
conf.map "nick :nick",
  :action => 'bot_nick'
conf.map "status",
  :action => 'bot_status',
  :auth_path => 'show::status'
# TODO see above
#
# conf.map "registry stats",
#   :action => 'bot_reg_stat',
#   :auth_path => '!config::status'
conf.map "version",
  :action => 'bot_version',
  :auth_path => 'show::status'

conf.map 'config set :key *value',
  :action => 'handle_set',
  :auth_path => 'edit'
conf.map 'config add :value to :key',
  :action => 'handle_add',
  :auth_path => 'edit'
conf.map 'config rm :value from :key',
  :action => 'handle_rm',
  :auth_path => 'edit'
conf.map 'config del :value from :key',
  :action => 'handle_rm',
  :auth_path => 'edit'
conf.map 'config delete :value from :key',
  :action => 'handle_rm',
  :auth_path => 'edit'
conf.map 'config unset :key',
  :action => 'handle_unset',
  :auth_path => 'edit'
conf.map 'config reset :key',
  :action => 'handle_unset',
  :auth_path => 'edit'

conf.map 'config help :topic',
  :action => 'handle_help',
  :defaults => {:topic => false},
  :auth_path => '!help!'

conf.default_auth('*', false)
conf.default_auth('show::status', true)
# TODO these shouldn't be set here, we need a way to let the default
# permission be specified together with the BotConfigValue
conf.default_auth('key', true)
conf.default_auth('key::auth::password', false)

