#-- vim:sw=2:et
#++
#
# :title: Spell plugin

class SpellPlugin < Plugin
  Config.register Config::StringValue.new('spell.path',
     :default => '/usr/bin/ispell',
     :desc => _('Path to the program to use to check spelling'))
  Config.register Config::StringValue.new('spell.command_line',
     :default => '%s -a -S',
     :desc => _('Command line used to call the spell.program. Use %s as a placeholder for the executable name'))

  def help(plugin, topic="")
    _("spell <word> => check spelling of <word>, suggest alternatives")
  end
  def privmsg(m)
    unless(m.params && m.params =~ /^\S+$/)
      m.reply _("incorrect usage: ") + help(m.plugin)
      return
    end

    begin
      IO.popen(@bot.config['spell.command_line'] % @bot.config['spell.program'], "w+") { |p|
        p.puts m.params
        p.close_write
        p.each_line { |l|
          case l
          when /^\*/
            m.reply(_("%{word} may be spelled correctly") % {:word => m.params})
          when /^\s*&.*: (.*)$/
            m.reply "#{m.params}: #$1"
          when /^\s*\+ (.*)$/
            m.reply((_("%{word} is presumably derived from ") % {:word => m.params}) + $1.downcase)
          when /^\s*#/
            m.reply(_("%{word}: no suggestions") % {:word => m.params})
          end
          return if m.replied?
        }
      }
    rescue
      m.reply(_("couldn't exec %{prog} :(") % {:prog => @bot.config['spell.program']})
      return
    end
    m.reply(_("something odd happened while checking %{word} with %{prog}") % {
      :word => m.params, :prog => @bot.config['spell.program']
    })
  end
end
plugin = SpellPlugin.new
plugin.register("spell")
