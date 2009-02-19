#  Author:    Michael Brailsford  <brailsmt@yahoo.com>
#             aka brailsmt
#  Purpose:   Provides the ability to track various tokens that are spoken in a
#             channel.
#  Copyright: 2002 Michael Brailsford.  All rights reserved.
#  License:   This plugin is licensed under the BSD license.  The terms of
#             which follow.
#
#  Redistribution and use in source and binary forms, with or without
#  modification, are permitted provided that the following conditions
#  are met:
#
#  1. Redistributions of source code must retain the above copyright notice,
#     this list of conditions and the following disclaimer.
#
#  2. Redistributions in binary form must reproduce the above copyright
#     notice, this list of conditions and the following disclaimer in the
#     documentation and/or other materials provided with the distribution.

class StatsPlugin < Plugin

	@@commands = {
		"stats" => "handle_stats",
		"track" => "handle_track",
		"untrack" => "handle_untrack",
		"listtokens" => "handle_listtokens",
		"rmabuser" => "handle_rmabuser"
	}

	#{{{
	def initialize
		super
		@listen = true
		@channels = Hash.new
		#check to see if a stats token file already exists for this channel...
		Dir["#{@bot.botclass}/stats/*"].each { |fname|
			channel = File.basename fname
			tokens = Hash.new
			IO.foreach(fname) { |line|
				if line =~ /^(\S+)\s*<=>(.*)/
					tokens[$1] = parse_token_stats $2
				end
			}
			@channels[channel] = tokens
		}
	end
	#}}}
	#{{{
	def cleanup
		@channels = nil
	end
	#}}}
	#{{{
	def help(plugin, topic="")
		"Stats:  The stats plugin tracks various tokens from users in the channel.  The tokens are only tracked if it is the only thing on a line.\nUsage:  stats <token>  --  lists the stats for <token>\n        [un]track <token>  --  Adds or deletes <token> from the list of tokens\n        listtokens  --  lists the tokens that are currently being tracked"
	end
	#}}}
	#{{{
	def privmsg(m)
		if not m.params and not m.plugin =~ /listtokens/
			m.reply "What a crazy fool!  Did you mean |help stats?"
			return
		end

		meth = self.method(@@commands[m.plugin])
		meth.call(m)
	end
	#}}}
	#{{{
	def save
		Dir.mkdir("#{@bot.botclass}/stats") if not FileTest.directory?("#{@bot.botclass}/stats")
		#save the tokens to a file...
		@channels.each_pair { |channel, tokens|
			if not tokens.empty?
				File.open("#{@bot.botclass}/stats/#{channel}", "w") { |f|
					tokens.each { |token, datahash|
						f.puts "#{token} <=> #{datahash_to_s(datahash)}"
					}
				}
			else
				File.delete "#{@bot.botclass}/stats/#{channel}"
			end
		}
	end
	#}}}
	#{{{
	def listen(m)
		if not m.private?
			tokens = @channels[m.target]
			if not @@commands[m.plugin]
				tokens.each_pair { |key, hsh|
					if not m.message.scan(/#{Regexp.escape(key)}/).empty?
						if hsh[m.sourcenick]
							hsh[m.sourcenick] += 1
						else
							hsh[m.sourcenick] = 1
						end
					end
				}
			end
		end
#This is the old code	{{{
#		if not m.private?
#			tokens = @channels[m.target]
#			hsh = tokens[m.message]
#			if hsh
#				if hsh[m.sourcenick]
#					hsh[m.sourcenick] += 1
#				else
#					hsh[m.sourcenick] = 1
#				end
#			end
#		end	}}}
	end
	#}}}
	#The following are helper functions for the plugin	{{{
		def datahash_to_s(dhash)
			rv = ""
			dhash.each { |key, val|
				rv << "#{key}:#{val} "
			}
			rv.chomp
		end

		def parse_token_stats(stats)
			rv = Hash.new
			stats.split(" ").each { |nickstat|
				nick, stat = nickstat.split ":"
				rv[nick] = stat.to_i
			}
			rv
		end
		#}}}
	#The following are handler methods for dealing with each command from IRC	{{{
	#{{{
	def handle_stats(m)
		if not m.private?
			total = 0
			tokens = @channels[m.target]
			hsh = tokens[m.params]
			msg1 = ""
			if not hsh.empty?
				sorted = hsh.sort { |i, j| j[1] <=> i[1] }
				sorted.each { |a|
					total += a[1]
				}

				msg = "Stats for #{m.params}.  Said #{total} times.  The top sayers are "
				if sorted[0..2]
					msg << "#{sorted[0].join ':'}" if sorted[0]
					msg << ", #{sorted[1].join ':'}" if sorted[1]
					msg << ", and #{sorted[2].join ':'}" if sorted[2]
					msg << "."

					msg1 << "#{m.sourcenick} has said it "
					if hsh[m.sourcenick]
						msg1 << "#{hsh[m.sourcenick]} times."
					else
						msg1 << "0 times."
					end
				else
					msg << "#{m.params} has not been said yet!"
				end
				@bot.action m.replyto, msg
				@bot.action m.replyto, msg1 if msg1
			else
				m.reply "#{m.params} is not currently being tracked."
			end
		end
	end
	#}}}
	#{{{
	def handle_track(m)
		if not m.private?
			if @channels[m.target]
				tokens = @channels[m.target]
			else
				tokens = Hash.new
				@channels[m.target] = tokens
			end
			tokens[m.params] = Hash.new
			m.reply "now tracking #{m.params}"
		end
	end
	#}}}
	#{{{
	def handle_untrack(m)
		if not m.private?
			toks = @channels[m.target]
			if toks.has_key? m.params
				toks.delete m.params
				m.reply "no longer tracking #{m.params}"
			else
				m.reply "Are your signals crossed?  Since when have I tracked that?"
			end
		end

		toks = nil
	end
	#}}}
	#{{{
	def handle_listtokens(m)
		if not m.private? and not @channels.empty?
			tokens = @channels[m.target]
			unless tokens.empty?
				toks = ""
				tokens.each_key { |k|
					toks << "#{k} "
				}
				@bot.action m.replyto, "is currently keeping stats for:  #{toks}"
			else
				@bot.action m.replyto, "is not currently keeping stats for anything"
			end
		elsif not m.private?
			@bot.action m.replyto, "is not currently keeping stats for anything"
		end
	end
	#}}}
	#{{{
	def handle_rmabuser(m)
		m.reply "This feature has not yet been implemented"
	end
	#}}}
	#}}}

end
plugin = StatsPlugin.new
plugin.register("stats")
plugin.register("track")
plugin.register("untrack")
plugin.register("listtokens")
#plugin.register("rmabuser")
