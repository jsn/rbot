#  Author:  Michael Brailsford  <brailsmt@yahoo.com>
#           aka  brailsmt
#  Purpose: To respond to requests for information from the ri command line
#  utility.

class RiPlugin < Plugin

	@@handlers = {
		"ri" => "ri_handler",
		"msgri" => "msgri_handler"
	}

	#{{{
	def initialize
		super
		@cache = Hash.new
	end
	#}}}
	#{{{
	def privmsg(m)
		if not m.params
			m.reply "uhmm... whatever"
			return
		end

		meth = self.method(@@handlers[m.plugin])
		meth.call(m)
	end
	#}}}
	#{{{
	def cleanup
		@cache = nil
	end
	#}}}
	#{{{
	def ri_handler(m)
		response = ""
		if @cache[m.params]
			response = @cache[m.params]
		else
			IO.popen("-") {|p|
				if(p)
					response = p.readlines.join "\n"
					@cache[m.params] = response
				else
					$stderr = $stdout
					exec("ri", m.params)
				end
			}
			@cache[m.params] = response
		end

		@bot.say m.sourcenick, response
		m.reply "Finished \"ri #{m.params}\"" 
	end
	#}}}
	#{{{
	def msgri_handler(m)
		response = ""
		tell_nick, query = m.params.split()
		if @cache[query]
			response = @cache[query]
		else
			IO.popen("-") {|p|
				if(p)
					response = p.readlines.join "\n"
					@cache[m.params] = response
				else
					$stderr = $stdout
					exec("ri", query)
				end
			}
			@cache[query] = response
		end

		@bot.say tell_nick, response
		m.reply "Finished telling #{tell_nick} about \"ri #{query}\"" 
	end
	#}}}
end
plugin = RiPlugin.new
plugin.register("ri")
plugin.register("msgri")
