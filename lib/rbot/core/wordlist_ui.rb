#-- vim:sw=2:et
#++
#
# :title: wordlist management from IRC
#
# Author:: Giuseppe "Oblomov" Bilotta <giuseppe.bilotta@gmail.com>

class WordlistModule < CoreBotModule
  def help(plugin, topic="")
    _("wordlist list [<pattern>] => list wordlists (matching <pattern>)")
  end

  def do_list(m, p)
    found = Wordlist.list(p)
    if found.empty?
      m.reply _("no wordlist found")
    else
      m.reply _("Wordlists: %{found}") % {
        :found => found.sort.join(', ')
      }
    end
  end
end

plugin = WordlistModule.new

plugin.map "wordlist list [:pattern]", :action => :do_list
