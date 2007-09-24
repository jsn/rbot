#-- vim:sw=2:et
#++
#
# :title: rbot user data management from IRC
#
# Author:: Giuseppe "Oblomov" Bilotta <giuseppe.bilotta@gmail.com>
# Copyright:: (C) 2006,2007 Giuseppe Bilotta
# License:: GPL v2

module ::Irc
  class User
    # Retrive Bot data associated with the receiver. This method is
    # intended for data retrieval only. See #set_bot_data() if you
    # need to alter User data.
    #
    def botdata(key=nil)
      Irc::Utils.bot.plugins['userdata'].get_data(self,key)
    end
    alias :get_botdata :botdata

    # This method is used to store Bot data associated with the
    # receiver. If no block is passed, _value_ is stored for the key
    # _key_; if a block is passed, it will be called with the previous
    # _key_ value as parameter, and its return value will be stored as
    # the new value. If _value_ is present in the block form, it will
    # be used to initialize _key_ if it's missing.
    #
    # If you have to do large-scale editing of the Bot data Hash,
    # please use with_botdata.
    # 
    def set_botdata(key, value=nil, &block)
      Irc::Utils.bot.plugins['userdata'].set_data(self, key, value, &block)
    end

    # This method yields the entire Bot data Hash to the block,
    # and stores any changes done to it, returning a copy
    # of the (changed) Hash.
    #
    def with_botdata(&block)
      Irc::Utils.bot.plugins['userdata'].with_data(self, &block)
    end

  end
end

# User data is stored in registries indexed by BotUser
# name and Irc::User nick. This core module takes care
# of handling its usage.
#
class UserDataModule < CoreBotModule

  def initialize
    super
    @ircuser = @registry.sub_registry('ircuser')
    @botuser = @registry.sub_registry('botuser')
  end

  def get_data_hash(user)
    iu = user.to_irc_user
    bu = iu.botuser

    ih = @ircuser[iu.nick] || {}

    if bu.transient? or bu.default?
      return ih
    else
      bh = @botuser[bu.username] || {}
      return ih.merge! bh
    end
  end

  def get_data(user, key=nil)
    h = get_data_hash(user)
    debug h
    return h if key.nil?
    return h[key]
  end

  def set_data_hash(user, h)
    iu = user.to_irc_user
    bu = iu.botuser

    if bu.transient? or bu.default?
      @ircuser[iu.nick] = h
    else
      @botuser[bu.username] = h
    end
  end

  def set_data(user, key, value=nil, &block)
    h = get_data_hash(user)
    debug h

    ret = value

    if not block_given?
      h[key] = value
    else
      if value and not h.has_key?(key)
        h[key] = value
      end
      ret = yield h[key]
    end
    debug ret

    set_data_hash(user, h)

    return ret
  end

  def with_data(user, &block)
    h = get_data_hash(user)
    debug h
    yield h

    set_data_hash(user, h)

    return h
  end

  def handle_get(m, params)
    user = m.server.get_user(params[:nick]) || m.source
    key = params[:key].intern
    data = get_data(user, key)
    if data
      m.reply (_("%{key} data for %{user}: %{data}") % {
        :key => key,
        :user => user.nick,
        :data => data
      })
    else
      m.reply (_("sorry, no %{key} data for %{user}") % {
        :key => key,
        :user => user.nick,
      })
    end
  end

  ### TODO FIXME not yet: are we going to allow non-string
  ### values for data? if so, this can't work ...
  #
  # def handle_set(m, params)
  #   user = m.server.get_user(params[:nick]) || m.source
  #   key = params[:key].intern
  #   data = params[:data].to_s
  # end

end

plugin = UserDataModule.new

plugin.map "get [:nick's] :key [data]",   :action => 'handle_get'
plugin.map "get :key [data] [for :nick]", :action => 'handle_get'
plugin.map "get :key [data] [of :nick]",  :action => 'handle_get'

# plugin.map "set [:nick's] :key [data] to :data", :action => handle_get
# plugin.map "set :key [data] [for :nick] to :data", :action => handle_get
# plugin.map "set :key [data] [of :nick] to :data", :action => handle_get
