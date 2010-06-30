# -*- coding: utf-8 -*-
#
# :title: Sed plugin
#
# Author:: MelmothX <melmothx@gmail.com>
# Copyright:: No copyright
# License:: Public Domain
#

class Sed < Plugin
  def initialize
    super
    # create the multidimensional hash 
    @amendlog = Hash.new
#    @answers = [
#                "voleva dire",
#                ", nella sua sbataggine, intendeva",
#                "si è sbagliato. Voleva dire",
#               ]
  end

  def help(plugin, topic="")
    "Fix the previous sentence using regexp and a sed-like syntax. Supported delimiters are /|,! and the modifier \"g\". Grouping is supported via parens, and backreferencing is done via \\1 \\2 and so on. You don't have to directly address the bot. Examples: <nick>hello <nick>s/e/u/"
  end
  
  def message(m)
    return unless m.public? 
    # log 
    source = m.source
    channel = m.channel
    stuff = m.message
    if not @amendlog.has_key?(channel)
      @amendlog[channel] = Hash.new
    end
    oldstring = @amendlog[channel][source] 
    newstring = oldstring
    if m.message.match(/^s([\/|,!])(.*?)\1(.*?)\1(g?)/) then
      target = Regexp.new($2)
      replace_with = $3
      global = $4
      if (global == "")
        newstring = oldstring.sub(target, replace_with)
      else
        newstring = oldstring.gsub(target, replace_with)
      end
#      sentence = @answers[rand(@answers.length)]
      sentence = _("meant")
      if (oldstring == newstring)
        failreply = _("You did something wrong... Try s/you/me/ or tell me \"help sed\"")
        m.reply("#{source}: #{failreply}")
        return
      end
      m.reply("#{source} #{sentence}: \"#{newstring}\"", :nick => false)
      return
    end
    @amendlog[channel][source] = stuff
  end
end
plugin = Sed.new

