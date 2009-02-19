#-- vim:sw=2:et
#++
#
# :title: rbot user data management from IRC
#
# Author:: Giuseppe "Oblomov" Bilotta <giuseppe.bilotta@gmail.com>

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

    # This method removes the data associated with the key, returning
    # the value of the deleted key.

    def delete_botdata(*keys)
      Irc::Utils.bot.plugins['userdata'].delete_data(self, *keys)
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
    @transient = @registry.sub_registry('transient')
    @botuser = @registry.sub_registry('botuser')
  end

  def get_data_hash(user, opts={})
    plain = opts[:plain]
    iu = user.to_irc_user
    bu = iu.botuser

    ih = @ircuser[iu.nick] || {}

    if bu.default?
      return ih
    elsif bu.transient?
      bh = @transient[bu.netmasks.first.fullform] || {}
    else
      bh = @botuser[bu.username] || {}
    end
    ih.merge!(bh)

    unless plain
      class << ih
        alias :single_retrieve :[]
        alias :single_assign :[]=
          include DottedIndex
      end
    end

    return ih
  end

  def get_data(user, key=nil)
    h = get_data_hash(user)
    debug h
    return h if key.nil?
    return h[key]
  end

  def set_data_hash(user, hh)
    iu = user.to_irc_user
    bu = iu.botuser

    # we .dup the hash to remove singleton methods
    # and make it dump-able
    h = hh.dup

    @ircuser[iu.nick] = h
    return h if bu.default?

    if bu.transient?
      @transient[bu.netmasks.first.fullform] = h
    else
      @botuser[bu.username] = h
    end
    return h
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

  def delete_data(user, *keys)
    h = get_data_hash(user)
    debug h
    rv = keys.map { |k| h.delete k }
    set_data_hash(user, h)
    rv.size == 1 ? rv.first : rv
  end

  def handle_get(m, params)
    user = m.server.get_user(params[:nick]) || m.source
    key = params[:key].intern
    data = get_data(user, key)
    if data
      m.reply(_("%{key} data for %{user}: %{data}") % {
        :key => key,
        :user => user.nick,
        :data => data
      })
    else
      m.reply(_("sorry, no %{key} data for %{user}") % {
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

  def event_botuser(action, opts={})
    case action
    when :copy, :rename
      source = opts[:source]
      return unless @botuser.key?(source)
      dest = opts[:dest]
      @botuser[dest] = @botuser[source].dup
      @botuser.delete(source) if action == :rename
    when :pre_perm
      @permification ||= {}
      k = [opts[:irc_user], opts[:bot_user]]
      @permification[k] = get_data_hash(opts[:irc_user], :plain => true)
    when :post_perm
      @permification ||= {}
      k = [opts[:irc_user], opts[:bot_user]]
      if @permification.has_key?(k)
        @botuser[opts[:bot_user]] = @permification[k]
        @permification.delete(k)
      end
    end
  end

end

plugin = UserDataModule.new

plugin.map "get [:nick's] :key [data]",   :action => 'handle_get'
plugin.map "get :key [data] [for :nick]", :action => 'handle_get'
plugin.map "get :key [data] [of :nick]",  :action => 'handle_get'

# plugin.map "set [:nick's] :key [data] to :data", :action => handle_get
# plugin.map "set :key [data] [for :nick] to :data", :action => handle_get
# plugin.map "set :key [data] [of :nick] to :data", :action => handle_get
