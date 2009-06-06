#++
#
# :title: Note plugin for rbot
#
# Author:: dmitry kim <dmitry dot kim at gmail dot com>
#
# Copyright:: (C) 200?-2009 dmitry 'jsn' kim
#
# License:: MIT license

class NotePlugin < Plugin
  Note = Struct.new('Note', :time, :from, :private, :text)

  def help(plugin, topic="")
    "note <nick> <string> => stores a note (<string>) for <nick>"
  end

  def message(m)
    begin
      return unless @registry.has_key? m.sourcenick
      pub = []
      priv = []
      @registry[m.sourcenick].each do |n|
        s = "[#{n.time.strftime('%H:%M')}] <#{n.from}> #{n.text}"
        (n.private ? priv : pub).push s
      end
      if !pub.empty?
        @bot.say m.replyto, "#{m.sourcenick}, you have notes! " +
          pub.join(' ')
      end

      if !priv.empty?
        @bot.say m.sourcenick, "you have notes! " + priv.join(' ')
      end
      @registry.delete m.sourcenick
    rescue Exception => e
      m.reply e.message
    end
  end

  def note(m, params)
    begin
      q = @registry[params[:nick]] || Array.new
      s = params[:string].to_s.strip
      raise 'cowardly discarding the empty note' if s.empty?
      q.push Note.new(Time.now, m.sourcenick, m.private?, s)
      @registry[params[:nick]] = q
      m.okay
    rescue Exception => e
      m.reply "error: #{e.message}"
    end
  end
end

NotePlugin.new.map 'note :nick *string'
