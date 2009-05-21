require 'pp'

# Keyword class
#
# Encapsulates a keyword ("foo is bar" is a keyword called foo, with type
# is, and has a single value of bar).
# Keywords can have multiple values, to_s() will choose one at random
class Keyword

  # type of keyword (e.g. "is" or "are")
  attr_reader :type

  # type::   type of keyword (e.g "is" or "are")
  # values:: array of values
  #
  # create a keyword of type +type+ with values +values+
  def initialize(type, values)
    @type = type.downcase
    @values = values
  end

  # pick a random value for this keyword and return it
  def to_s
    if(@values.length > 1)
      Keyword.unescape(@values[rand(@values.length)])
    else
      Keyword.unescape(@values[0])
    end
  end

  # return an array of all the possible values
  def to_factoids(key)
    ar = Array.new
    @values.each { |val|
      debug "key #{key}, value #{val}"
      vals = val.split(" or ")
      vals.each { |v|
        ar << "%s %s %s" % [key, @type, v]
      }
    }
    return ar
  end

  # describe the keyword (show all values without interpolation)
  def desc
    @values.join(" | ")
  end

  # return the keyword in a stringified form ready for storage
  def dump
    @type + "/" + Keyword.unescape(@values.join("<=or=>"))
  end

  # deserialize the stringified form to an object
  def Keyword.restore(str)
    if str =~ /^(\S+?)\/(.*)$/
      type = $1
      vals = $2.split("<=or=>")
      return Keyword.new(type, vals)
    end
    return nil
  end

  # values:: array of values to add
  # add values to a keyword
  def <<(values)
    if(@values.length > 1 || values.length > 1)
      values.each {|v|
        @values << v
      }
    else
      @values[0] += " or " + values[0]
    end
  end

  # unescape special words/characters in a keyword
  def Keyword.unescape(str)
    str.gsub(/\\\|/, "|").gsub(/ \\is /, " is ").gsub(/ \\are /, " are ").gsub(/\\\?(\s*)$/, "?\1")
  end

  # escape special words/characters in a keyword
  def Keyword.escape(str)
    str.gsub(/\|/, "\\|").gsub(/ is /, " \\is ").gsub(/ are /, " \\are ").gsub(/\?(\s*)$/, "\\?\1")
  end
end

# keywords class.
#
# Handles all that stuff like "bot: foo is bar", "bot: foo?"
#
# Fallback after core and auth have had a look at a message and refused to
# handle it, checks for a keyword command or lookup, otherwise the message
# is delegated to plugins
class Keywords < Plugin
  Config.register Config::BooleanValue.new('keyword.listen',
    :default => false,
    :desc => "Should the bot listen to all chat and attempt to automatically detect keywords? (e.g. by spotting someone say 'foo is bar')")
  Config.register Config::BooleanValue.new('keyword.address',
    :default => true,
    :desc => "Should the bot require that keyword lookups are addressed to it? If not, the bot will attempt to lookup foo if someone says 'foo?' in channel")
  Config.register Config::IntegerValue.new('keyword.search_results',
    :default => 3,
    :desc => "How many search results to display at a time")
  Config.register Config::ArrayValue.new('keyword.ignore_words',
    :default => ["how", "that", "these", "they", "this", "what", "when", "where", "who", "why", "you"],
    :desc => "A list of words that the bot should passively ignore.")

  # create a new KeywordPlugin instance, associated to bot +bot+
  def initialize
    super

    @statickeywords = Hash.new
    @keywords = @registry.sub_registry('keywords') # DBTree.new bot, "keyword"
    upgrade_data

    scan

    # import old format keywords into DBHash
    olds = @bot.path 'keywords.rbot'
    if File.exist? olds
      log "auto importing old keywords.rbot"
      IO.foreach(olds) do |line|
        if(line =~ /^(.*?)\s*<=(is|are)?=?>\s*(.*)$/)
          lhs = $1
          mhs = $2
          rhs = $3
          mhs = "is" unless mhs
          rhs = Keyword.escape rhs
          values = rhs.split("<=or=>")
          @keywords[lhs] = Keyword.new(mhs, values).dump
        end
      end
      File.rename(olds, olds + ".old")
    end
  end

  # load static keywords from files, picking up any new keyword files that
  # have been added
  def scan
    # first scan for old DBHash files, and convert them
    Dir[datafile('*')].each {|f|
      next unless f =~ /\.db$/
      log "upgrading keyword db #{f} (rbot 0.9.5 or prior) database format"
      newname = f.gsub(/\.db$/, ".kdb")
      old = BDB::Hash.open f, nil, "r+", 0600
      new = BDB::CIBtree.open(newname, nil, BDB::CREATE | BDB::EXCL, 0600)
      old.each {|k,v|
        new[k] = v
      }
      old.close
      new.close
      File.delete(f)
    }

    # then scan for current DBTree files, and load them
    Dir[@bot.path('keywords', '*')].each {|f|
      next unless f =~ /\.kdb$/
      hsh = DBTree.new @bot, f, true
      key = File.basename(f).gsub(/\.kdb$/, "")
      debug "keywords module: loading DBTree file #{f}, key #{key}"
      @statickeywords[key] = hsh
    }

    # then scan for non DB files, and convert/import them and delete
    Dir[@bot.path('keywords', '*')].each {|f|
      next if f =~ /\.kdb$/
      next if f =~ /CVS$/
      log "auto converting keywords from #{f}"
      key = File.basename(f)
      unless @statickeywords.has_key?(key)
        @statickeywords[key] = DBHash.new @bot, "#{f}.db", true
      end
      IO.foreach(f) {|line|
        if(line =~ /^(.*?)\s*<?=(is|are)?=?>\s*(.*)$/)
          lhs = $1
          mhs = $2
          rhs = $3
          # support infobot style factfiles, by fixing them up here
          rhs.gsub!(/\$who/, "<who>")
          mhs = "is" unless mhs
          rhs = Keyword.escape rhs
          values = rhs.split("<=or=>")
          @statickeywords[key][lhs] = Keyword.new(mhs, values).dump
        end
      }
      File.delete(f)
      @statickeywords[key].flush
    }
  end

  # upgrade data files found in old rbot formats to current
  def upgrade_data
    olds = @bot.path 'keywords.db'
    if File.exist? olds
      log "upgrading old keywords (rbot 0.9.5 or prior) database format"
      old = BDB::Hash.open olds, nil, "r+", 0600
      old.each {|k,v|
        @keywords[k] = v
      }
      old.close
      @keywords.flush
      File.rename(olds, olds + ".old")
    end

    olds.replace(@bot.path('keyword.db'))
    if File.exist? olds
      log "upgrading old keywords (rbot 0.9.9 or prior) database format"
      old = BDB::CIBtree.open olds, nil, "r+", 0600
      old.each {|k,v|
        @keywords[k] = v
      }
      old.close
      @keywords.flush
      File.rename(olds, olds + ".old")
    end
  end

  # save dynamic keywords to file
  def save
    @keywords.flush
  end

  def oldsave
    File.open(@bot.path("keywords.rbot"), "w") do |file|
      @keywords.each do |key, value|
        file.puts "#{key}<=#{value.type}=>#{value.dump}"
      end
    end
  end

  # lookup keyword +key+, return it or nil
  def [](key)
    return nil if key.nil?
    debug "keywords module: looking up key #{key}"
    if(@keywords.has_key?(key))
      return Keyword.restore(@keywords[key])
    else
      # key name order for the lookup through these
      @statickeywords.keys.sort.each {|k|
        v = @statickeywords[k]
        if v.has_key?(key)
          return Keyword.restore(v[key])
        end
      }
    end
    return nil
  end

  # does +key+ exist as a keyword?
  def has_key?(key)
    if @keywords.has_key?(key) && Keyword.restore(@keywords[key]) != nil
      return true
    end
    @statickeywords.each {|k,v|
      if v.has_key?(key) && Keyword.restore(v[key]) != nil
        return true
      end
    }
    return false
  end

  # is +word+ a passively ignored keyword?
  def ignored_word?(word)
    @bot.config["keyword.ignore_words"].include?(word)
  end

  # m::     PrivMessage containing message info
  # key::   key being queried
  # quiet:: optional, if false, complain if +key+ is not found
  #
  # handle a message asking about a keyword
  def keyword_lookup(m, key, quiet = false)
    return if key.nil?
    unless(kw = self[key])
      m.reply "sorry, I don't know about \"#{key}\"" unless quiet
      return
    end

    response = kw.to_s
    response.gsub!(/<who>/, m.sourcenick)

    if(response =~ /^<reply>\s*(.*)/)
      m.reply $1
    elsif(response =~ /^<action>\s*(.*)/)
      m.act $1
    elsif(m.public? && response =~ /^<topic>\s*(.*)/)
      @bot.topic m.target, $1
    else
      m.reply "#{key} #{kw.type} #{response}"
    end
  end


  # handle a message which alters a keyword
  # like "foo is bar" or "foo is also qux"
  def keyword_command(m, lhs, mhs, rhs, quiet = false)
    debug "got keyword command #{lhs}, #{mhs}, #{rhs}"
    return if lhs.strip.empty?

    overwrite = false
    overwrite = true if(lhs.gsub!(/^no,\s*/, ""))
    also = false
    also = true if(rhs.gsub!(/^also\s+/, ""))

    values = rhs.split(/\s+\|\s+/)
    lhs = Keyword.unescape lhs

    if(overwrite || also || !has_key?(lhs))
      if(also && has_key?(lhs))
        kw = self[lhs]
        kw << values
        @keywords[lhs] = kw.dump
      else
        @keywords[lhs] = Keyword.new(mhs, values).dump
      end
      m.okay if !quiet
    elsif(has_key?(lhs))
      kw = self[lhs]
      m.reply "but #{lhs} #{kw.type} #{kw.desc}" if kw && !quiet
    end
  end

  # return help string for Keywords with option topic +topic+
  def help(plugin, topic = '')
    case plugin
    when /keyword/
      case topic
      when 'export'
        'keyword export => exports definitions to keyword_factoids.rbot'
      when 'stats'
        'keyword stats => show statistics about static facts'
      when 'wipe'
        'keyword wipe <keyword> => forgets everything about a keyword'
      when 'lookup'
        'keyword [lookup] <keyword> => look up the definition for a keyword; writing "lookup" is optional'
      when 'set'
        'keyword set <keyword> is/are <definition> => define a keyword, definition can contain "|" to separate multiple randomly chosen replies'
      when 'forget'
        'keyword forget <keyword> => forget a keyword'
      when 'tell'
        'keyword tell <nick> about <keyword> => tell somebody about a keyword'
      when 'search'
        'keyword search [--all] [--full] <pattern> => search keywords for <pattern>, which can be a regular expression. If --all is set, search static keywords too, if --full is set, search definitions too.'
      when 'listen'
        'when the config option "keyword.listen" is set to false, rbot will try to extract keyword definitions from regular channel messages'
      when 'address'
        'when the config option "keyword.address" is set to true, rbot will try to answer channel questions of the form "<keyword>?"'
      when '<reply>'
        '<reply> => normal response is "<keyword> is <definition>", but if <definition> begins with <reply>, the response will be "<definition>"'
      when '<action>'
        '<action> => makes keyword respond with "/me <definition>"'
      when '<who>'
        '<who> => replaced with questioner in reply'
      when '<topic>'
        '<topic> => respond by setting the topic to the rest of the definition'
      else
        'keyword module (fact learning and regurgitation) topics: lookup, set, forget, tell, search, listen, address, stats, export, wipe, <reply>, <action>, <who>, <topic>'
      end
    when "forget"
      'forget <keyword> => forget a keyword'
    when "tell"
      'tell <nick> about <keyword> => tell somebody about a keyword'
    when "learn"
      'learn that <keyword> is/are <definition> => define a keyword, definition can contain "|" to separate multiple randomly chosen replies'
    else
      'keyword module (fact learning and regurgitation) topics: lookup, set, forget, tell, search, listen, address, <reply>, <action>, <who>, <topic>'
    end
  end

  # handle a message asking the bot to tell someone about a keyword
  def keyword_tell(m, target, key)
    unless(kw = self[key])
      m.reply @bot.lang.get("dunno_about_X") % key
      return
    end
    if target == @bot.nick
      m.reply "very funny, trying to make me tell something to myself"
      return
    end

    response = kw.to_s
    response.gsub!(/<who>/, m.sourcenick)
    if(response =~ /^<reply>\s*(.*)/)
      @bot.say target, "#{m.sourcenick} wanted me to tell you: (#{key}) #$1"
      m.reply "okay, I told #{target}: (#{key}) #$1"
    elsif(response =~ /^<action>\s*(.*)/)
      @bot.action target, "#$1 (#{m.sourcenick} wanted me to tell you)"
      m.reply "okay, I told #{target}: * #$1"
    else
      @bot.say target, "#{m.sourcenick} wanted me to tell you that #{key} #{kw.type} #{response}"
      m.reply "okay, I told #{target} that #{key} #{kw.type} #{response}"
    end
  end

  # return the number of known keywords
  def keyword_stats(m)
    length = 0
    @statickeywords.each {|k,v|
      length += v.length
    }
    m.reply "There are currently #{@keywords.length} keywords, #{length} static facts defined."
  end

  # search for keywords, optionally also the definition and the static keywords
  def keyword_search(m, key, full = false, all = false, from = 1)
    begin
      if key =~ /^\/(.+)\/$/
        re = Regexp.new($1, Regexp::IGNORECASE)
      else
        re = Regexp.new(Regexp.escape(key), Regexp::IGNORECASE)
      end

      matches = Array.new
      @keywords.each {|k,v|
        kw = Keyword.restore(v)
        if re.match(k) || (full && re.match(kw.desc))
          matches << [k,kw]
        end
      }
      if all
        @statickeywords.each {|k,v|
          v.each {|kk,vv|
            kw = Keyword.restore(vv)
            if re.match(kk) || (full && re.match(kw.desc))
              matches << [kk,kw]
            end
          }
        }
      end

      if matches.length == 1
        rkw = matches[0]
        m.reply "#{rkw[0]} #{rkw[1].type} #{rkw[1].desc}"
      elsif matches.length > 0
        if from > matches.length
          m.reply "#{matches.length} found, can't tell you about #{from}"
          return
        end
        i = 1
        matches.each {|rkw|
          m.reply "[#{i}/#{matches.length}] #{rkw[0]} #{rkw[1].type} #{rkw[1].desc}" if i >= from
          i += 1
          break if i == from+@bot.config['keyword.search_results']
        }
      else
        m.reply "no keywords match #{key}"
      end
    rescue RegexpError => e
      m.reply "no keywords match #{key}: #{e}"
    rescue
      debug e.inspect
      m.reply "no keywords match #{key}: an error occurred"
    end
  end

  # forget one of the dynamic keywords
  def keyword_forget(m, key)
    if @keywords.delete(key)
      m.okay
    else
      m.reply _("couldn't find keyword %{key}" % { :key => key })
    end
  end

  # low-level keyword wipe command for when forget doesn't work
  def keyword_wipe(m, key)
    reg = @keywords.registry
    reg.env.begin(reg) { |t, b|
      b.delete_if { |k, v|
        (k == key) && (m.reply "wiping keyword #{key} with stored value #{Marshal.restore(v)}")
      }
      t.commit
    }
    m.reply "done"
  end

  # export keywords to factoids file
  def keyword_factoids_export
    ar = Array.new

    debug @keywords.keys

    @keywords.each { |k, val|
      next unless val
      kw = Keyword.restore(val)
      ar |= kw.to_factoids(k)
    }

    # TODO check factoids config
    # also TODO: runtime export
    dir = @bot.path 'factoids'
    fname = File.join(dir,"keyword_factoids.rbot")

    Dir.mkdir(dir) unless FileTest.directory?(dir)
    Utils.safe_save(fname) do |file|
      file.puts ar
    end
  end

  # privmsg handler
  def privmsg(m)
    case m.plugin
    when "keyword"
      case m.params
      when /^export$/
        begin
          keyword_factoids_export
          m.okay
        rescue
          m.reply _("failed to export keywords as factoids (%{err})" % {:err => $!})
        end
      when /^set\s+(.+?)\s+(is|are)\s+(.+)$/
        keyword_command(m, $1, $2, $3) if @bot.auth.allow?('keycmd', m.source, m.replyto)
      when /^forget\s+(.+)$/
        keyword_forget(m, $1) if @bot.auth.allow?('keycmd', m.source, m.replyto)
      when /^wipe\s(.+)$/ # note that only one space is stripped, allowing removal of space-prefixed keywords
        keyword_wipe(m, $1) if @bot.auth.allow?('keycmd', m.source, m.replyto)
      when /^lookup\s+(.+)$/
        keyword_lookup(m, $1) if @bot.auth.allow?('keyword', m.source, m.replyto)
      when /^stats\s*$/
        keyword_stats(m) if @bot.auth.allow?('keyword', m.source, m.replyto)
      when /^search\s+(.+)$/
        key = $1
        full = key.sub!('--full ', '')
        all = key.sub!('--all ', '')
        if key.sub!(/--from (\d+) /, '')
          from = $1.to_i
        else
          from = 1
        end
        from = 1 unless from > 0
        keyword_search(m, key, full, all, from) if @bot.auth.allow?('keyword', m.source, m.replyto)
      when /^tell\s+(\S+)\s+about\s+(.+)$/
        keyword_tell(m, $1, $2) if @bot.auth.allow?('keyword', m.source, m.replyto)
      else
        keyword_lookup(m, m.params) if @bot.auth.allow?('keyword', m.source, m.replyto)
      end
    when "forget"
      keyword_forget(m, m.params) if @bot.auth.allow?('keycmd', m.source, m.replyto)
    when "tell"
      if m.params =~ /(\S+)\s+about\s+(.+)$/
        keyword_tell(m, $1, $2) if @bot.auth.allow?('keyword', m.source, m.replyto)
      else
        m.reply "wrong 'tell' syntax"
      end
    when "learn"
      if m.params =~ /^that\s+(.+?)\s+(is|are)\s+(.+)$/
        keyword_command(m, $1, $2, $3) if @bot.auth.allow?('keycmd', m.source, m.replyto)
      else
        m.reply "wrong 'learn' syntax"
      end
    end
  end

  def unreplied(m)
    # TODO option to do if(m.message =~ /^(.*)$/, ie try any line as a
    # keyword lookup.
    if m.message =~ /^(.*\S)\s*\?\s*$/ and (m.address? or not @bot.config["keyword.address"])
      keyword_lookup m, $1, true if !ignored_word?($1) && @bot.auth.allow?("keyword", m.source)
    elsif @bot.config["keyword.listen"] && (m.message =~ /^(.*?)\s+(is|are)\s+(.*)$/)
      # TODO MUCH more selective on what's allowed here
      keyword_command m, $1, $2, $3, true if !ignored_word?($1) && @bot.auth.allow?("keycmd", m.source)
    end
  end
end

plugin = Keywords.new
plugin.register 'keyword'
plugin.register 'forget' rescue nil
plugin.register 'tell' rescue nil
plugin.register 'learn' rescue nil

