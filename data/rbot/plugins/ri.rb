#-- vim:sw=2:et
#++
#
# :title: 'ri' -- ruby documentation plugin
#
# Author:: Eric Hodel <drbrain@segment7.net> (aka drbrain)
# Author:: Michael Brailsford  <brailsmt@yahoo.com> aka brailsmt
# Author:: dmitry kim <dmitry dot kim at gmail dot com>
# Copyright:: (C) 2007, dmitry kim
# Copyright:: (C) Eric Hodel
# Copyright:: (C) Michael Brailsford
# License:: MIT
#

class RiPlugin < Plugin

  RI_COMMAND = %w{ri -f simple -T}

  BotConfig.register BotConfigIntegerValue.new('ri.max_length',
    :default => 512,
    :desc => "Maximum length of ri entry (in bytes) which is ok to be sent to channels or other users")

  def help(plugin, topic="")
    "ri <something> => returns ruby documentation for <something>; ri [tell] <whom> [about] <something> => sends the documentation entry about <something> to <whom> using /msg"
  end

  def ri(m, params)
    tgt = nil
    if params[:who]
      if m.private?
        if params[:who] != m.sourcenick
          m.reply '"ri tell <who>" syntax is only allowed in public channels'
          return
        end
      elsif !(tgt = m.channel.users[params[:who]])
        m.reply "sorry, i don't see user #{params[:who]} here on #{m.channel}"
        return
      end
    end
    args = RI_COMMAND.dup
    if a = params[:something]
      if a == '-c'
        args.push(a)
      else
        args.push('--')
        args.push(a)
      end
    end
    begin
      ret = Utils.safe_exec(*args)
    rescue
      return m.reply("failed to execute ri")
    end
    ret = ret.gsub(/\t/, "  ").split(/\n/).join(" ").gsub(/\s\s+/, '  ')
    
    if ret.length > @bot.config['ri.max_length'] && !m.private?
      return m.reply('entry is too long to send to the channel or to some other user, use /msg to ask me about it')
    end
    if tgt
      @bot.say(tgt, ret)
    else
      m.reply(ret)
    end
    return
  end
end

plugin = RiPlugin.new
plugin.map 'ri :something', :requirements => {:something => /^((-c)|(\w\S+))$/}
plugin.map 'ri [tell] :who [about] :something',
  :requirements => {:something => /^((-c)|(\w\S+))$/}
