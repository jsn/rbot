#----------------------------------------------------------------#
# Filename: vandale.rb
# Description: Rbot plugin. Looks up a word in the Dutch VanDale
# 	dictionary
# Author: eWoud - ewoud.nuyts<AT>student.kuleuven.ac.be
# requires GnuVD www.djcbsoftware.nl/projecten/gnuvd/
#----------------------------------------------------------------#

class VanDalePlugin < Plugin
  def help(plugin, topic="")
    "vandale [<word>] => Look up in the VanDale dictionary"
  end
  def privmsg(m)
	case m.params
	when (/^([\w-]+)$/)
		ret = Array.new
		Utils.safe_exec("/usr/local/bin/gnuvd", m.params).each{|line| if line.length > 5 then ret << line end}
		m.reply ret.delete_at(0)
		while ret[0] =~ /^[[:alpha:]_]*[0-9]/ 
			m.reply ret.delete_at(0)
		end
		while ret[0] =~ /^[0-9]/
			m.reply ret.delete_at(0)
		end
		i = 0
		while i < ret.length
			ret[i] = ret[i].slice(/^[[:graph:]_]*/)
			if ret[i].length == 0 or ret[i] =~ /^[0-9]/
			then
				ret.delete_at(i)
			else
				i = i+1
			end
		end
		if ret.length != 0 then
			m.reply "zie ook " + ret.join(", ")
		end
		return
	when nil
		m.reply "incorrect usage: " + help(m.plugin)
		return
	else
		m.reply "incorrect usage: " + help(m.plugin)
		return
	end
  end
end
plugin = VanDalePlugin.new
plugin.register("vandale")
