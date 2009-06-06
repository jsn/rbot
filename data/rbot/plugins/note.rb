Note = Struct.new('Note', :time, :from, :private, :text)

class NotePlugin < Plugin
  def help(plugin, topic="")
    "note <nick> <string> => stores a note (<string>) for <nick>"
  end

  def listen(m)
    begin
      return if !m.kind_of?(PrivMessage) || !@registry.has_key?(m.sourcenick)
      pub = []
      priv = []
      @registry[m.sourcenick].each do |n|
        s = "[#{n.time.strftime('%H:%M')}] <#{n.from}> #{n.text}"
        (n.private ? priv : pub).push(s)
      end
      if !pub.empty?
        @bot.say m.replyto, "#{m.sourcenick}, you have notes! " +
          pub.join(' ')
      end

      if !priv.empty?
        @bot.say m.sourcenick, "you have notes! " + priv.join(' ')
      end
      @registry.delete(m.sourcenick)
    rescue Exception => e
      m.reply e.message
    end
  end

  def note(m, params)
    begin
      q = @registry[params[:nick]] || Array.new
      s = params[:string].join(' ')
      raise 'cowardly discarding the empty note' if s.empty? || !s =~ /\S/
      q.push Note.new(Time.now, m.sourcenick,
                      m.private?, params[:string].join(' '))
      @registry[params[:nick]] = q
      m.okay
    rescue Exception => e
      m.reply "error: #{e.message}"
    end
  end
end
plugin = NotePlugin.new
plugin.map 'note :nick *string'
