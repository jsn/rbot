class SpellPlugin < Plugin
  def help(plugin, topic="")
    "spell <word> => check spelling of <word>, suggest alternatives"
  end
  def privmsg(m)
    unless(m.params && m.params =~ /^\S+$/)
      m.reply "incorrect usage: " + help(m.plugin)
      return
    end
    p = IO.popen("ispell -a -S", "w+")
    if(p)
      p.puts m.params
      p.close_write
      p.each_line {|l|
        if(l =~ /^\*/)
          m.reply "#{m.params} may be spelled correctly"
          p.close
          return
        elsif(l =~ /^\s*&.*: (.*)$/)
          m.reply "#{m.params}: #$1"
          p.close
          return
        elsif(l =~ /^\s*\+ (.*)$/)
          m.reply "#{m.params} is presumably derived from " + $1.downcase
          p.close
          return
        elsif(l =~ /^\s*#/)
          m.reply "#{m.params}: no suggestions"
          p.close
          return
        end
      }
      p.close
    else
      m.reply "couldn't exec ispell :("
      return
    end
  end
end
plugin = SpellPlugin.new
plugin.register("spell")
