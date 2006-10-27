#  Original Author:
#               Michael Brailsford  <brailsmt@yahoo.com>
#               aka brailsmt
#  Author:      Giuseppe "Oblomov" Bilotta <giuseppe.bilotta@gmail.com>
#  Purpose:     Provide for humorous larts and praises
#  Original Copyright:
#               2002 Michael Brailsford.  All rights reserved.
#  Copyright:   2006 Giuseppe Bilotta.  All rights reserved.
#  License:     This plugin is licensed under the BSD license.  The terms of
#               which follow.
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

class LartPlugin < Plugin

  # Keep a 1:1 relation between commands and handlers
  @@handlers = {
    "lart" => "handle_lart",
    "praise" => "handle_praise",
    "addlart" => "handle_addlart",
    "rmlart" => "handle_rmlart",
    "addpraise" => "handle_addpraise",
    "rmpraise" => "handle_rmpraise"
  }

  def name
    "lart"
  end

  def initialize
    @larts = Array.new
    @praises = Array.new
    @lartfile = nil
    @praisefile = nil
    super

  end

  def set_language(lang)
    save
    @lartfile = "#{@bot.botclass}/lart/larts-#{lang}"
    @praisefile = "#{@bot.botclass}/lart/praises-#{lang}"
    # We may be on an old installation, so on the first run read non-language-specific larts
    @bulart = "#{@bot.botclass}/lart/larts"
    @bupraise = "#{@bot.botclass}/lart/praise"
    @larts.clear
    @praises.clear
    if File.exists? @lartfile
      IO.foreach(@lartfile) { |line|
        @larts << line.chomp
      }
    elsif File.exists? @bulart
      IO.foreach(@bulart) { |line|
        @larts << line.chomp
      }
    end
    if File.exists? @praisefile
      IO.foreach(@praisefile) { |line|
        @praises << line.chomp
      }
    elsif File.exists? @bupraise
      IO.foreach(@bupraise) { |line|
        @praises << line.chomp
      }
    end
  end

  def cleanup
  end

  def save
    return if @lartfile.nil? and @praisefile.nil?
    Dir.mkdir("#{@bot.botclass}/lart") if not FileTest.directory? "#{@bot.botclass}/lart"
    # TODO implement safe saving here too
    Utils.safe_save(@lartfile) { |file|
      file.puts @larts
    }
    Utils.safe_save(@praisefile) { |file|
      file.puts @praises
    }
  end

  def privmsg(m)
    if not m.params
      m.reply "What a crazy fool!  Did you mean |help stats?"
      return
    end

    meth = self.method(@@handlers[m.plugin])
    meth.call(m) if(@bot.auth.allow?(m.plugin, m.source, m.replyto))
  end

  def help(plugin, topic="")
    "Lart: The lart plugin allows you to lart/praise someone in the channel. You can also add new larts and new praises as well as delete them. For the curious, LART is an acronym for Luser Attitude Readjustment Tool. Usage: lart <who> [<reason>] -- larts <who> for <reason>. praise <who> [<reason>] -- praises <who> for <reason>. [add|rm][lart|praise] -- Add or remove a lart or praise."
  end

  # The following are command handler

  def handle_lart(m)
    for_idx = m.params =~ /\s+\bfor\b/
    if for_idx
      nick = m.params[0, for_idx]
    else
      nick = m.params
    end
    lart = @larts[get_msg_idx(@larts.length)]
    if lart == nil
      m.reply "I dunno any larts"
      return
    end
    if nick == @bot.nick
      lart = replace_who lart, m.sourcenick
      lart << " for trying to make me lart myself"
    else
      lart = replace_who lart, nick
      lart << m.params[for_idx, m.params.length] if for_idx
    end

    @bot.action m.replyto, lart
  end

  def handle_praise(m)
    for_idx = m.params =~ /\s+\bfor\b/
    if for_idx
      nick = m.params[0, for_idx]
    else
      nick = m.params
    end
    praise = @praises[get_msg_idx(@praises.length)]
    if not praise
      m.reply "I dunno any praises"
      return
    end

    if nick == m.sourcenick
      praise = @larts[get_msg_idx(@larts.length)]
      praise = replace_who praise, nick
    else
      praise = replace_who praise, nick
      praise << m.params.gsub("#{nick}", "")
    end

    @bot.action m.replyto, praise
  end

  def handle_addlart(m)
    @larts << m.params
    m.okay
  end

  def handle_rmlart(m)
    @larts.delete m.params
    m.okay
  end

  def handle_addpraise(m)
    @praises << m.params
    m.okay
  end

  def handle_rmpraise(m)
    @praises.delete m.params
    m.okay
  end

  #  The following are utils for larts/praises
  def replace_who(msg, nick)
    msg.gsub(/<who>/i, "#{nick}")
  end

  def get_msg_idx(max)
    idx = rand(max)
  end

end
plugin = LartPlugin.new
plugin.register("lart")
plugin.register("praise")

plugin.register("addlart")
plugin.register("addpraise")

plugin.register("rmlart")
plugin.register("rmpraise")
