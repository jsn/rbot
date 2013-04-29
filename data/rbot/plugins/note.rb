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

  Config.register Config::BooleanValue.new 'note.private_message',
    :default => false,
    :desc => 'Send all notes in private messages instead of channel messages.'

  def initialize
    super
    return if @registry.length < 1
    debug 'Checking registry for old-formatted notes...'
    n = 0
    @registry.keys.each do |key|
      unless key == key.downcase
        @registry[key.downcase] = @registry[key] + (@registry[key.downcase] || [])
        @registry.delete key
        n += 1
      end
    end
    debug "#{n} entries converted and merged."
  end

  def help(plugin, topic='')
    'note <nick> <string> => stores a note (<string>) for <nick>'
  end

  def message(m)
    begin
      nick = m.sourcenick.downcase
      # Keys are case insensitive to avoid storing a message
      # for <person> instead of <Person> or visa-versa.
      return unless @registry.has_key? nick
      pub = []
      priv = []
      @registry[nick].each do |n|
        s = "[#{n.time.strftime('%b-%e %H:%M')}] <#{n.from}> #{n.text}"
        if n.private or @bot.config['note.private_message']
          priv << s
        else
          pub << s
        end
      end
      unless pub.empty?
        @bot.say m.replyto, "#{m.sourcenick}, you have notes! " +
          pub.join(' ')
      end
      unless priv.empty?
        @bot.say m.sourcenick, 'you have notes! ' + priv.join(' ')
      end
      @registry.delete nick
    rescue Exception => e
      m.reply e.message
    end
  end

  def note(m, params)
    begin
      nick = params[:nick].downcase
      q = @registry[nick] || Array.new
      s = params[:string].to_s.strip
      raise 'cowardly discarding the empty note' if s.empty?
      q.push Note.new(Time.now, m.sourcenick, m.private?, s)
      @registry[nick] = q
      m.okay
    rescue Exception => e
      m.reply "error: #{e.message}"
    end
  end
end

NotePlugin.new.map 'note :nick *string'
