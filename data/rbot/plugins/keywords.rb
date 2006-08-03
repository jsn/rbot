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
  BotConfig.register BotConfigBooleanValue.new('keyword.listen',
    :default => false,
    :desc => "Should the bot listen to all chat and attempt to automatically detect keywords? (e.g. by spotting someone say 'foo is bar')")
  BotConfig.register BotConfigBooleanValue.new('keyword.address',
    :default => true,
    :desc => "Should the bot require that keyword lookups are addressed to it? If not, the bot will attempt to lookup foo if someone says 'foo?' in channel")
  
  # create a new Keywords instance, associated to bot +bot+
  def initialize
    super

    @statickeywords = Hash.new
    @keywords = @registry.sub_registry('keywords') # DBTree.new bot, "keyword"
    upgrade_data

    scan
    
    # import old format keywords into DBHash
    if(File.exist?("#{@bot.botclass}/keywords.rbot"))
      log "auto importing old keywords.rbot"
      IO.foreach("#{@bot.botclass}/keywords.rbot") do |line|
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
      File.rename("#{@bot.botclass}/keywords.rbot", "#{@bot.botclass}/keywords.rbot.old")
    end
  end
  
  # drop static keywords and reload them from files, picking up any new
  # keyword files that have been added
  def rescan
    @statickeywords = Hash.new
    scan
  end

  # load static keywords from files, picking up any new keyword files that
  # have been added
  def scan
    # first scan for old DBHash files, and convert them
    Dir["#{@bot.botclass}/keywords/*"].each {|f|
      next unless f =~ /\.db$/
      log "upgrading keyword db #{f} (rbot 0.9.5 or prior) database format"
      newname = f.gsub(/\.db$/, ".kdb")
      old = BDB::Hash.open f, nil, 
                           "r+", 0600
      new = BDB::CIBtree.open(newname, nil, 
                              BDB::CREATE | BDB::EXCL,
                              0600)
      old.each {|k,v|
        new[k] = v
      }
      old.close
      new.close
      File.delete(f)
    }
    
    # then scan for current DBTree files, and load them
    Dir["#{@bot.botclass}/keywords/*"].each {|f|
      next unless f =~ /\.kdb$/
      hsh = DBTree.new @bot, f, true
      key = File.basename(f).gsub(/\.kdb$/, "")
      debug "keywords module: loading DBTree file #{f}, key #{key}"
      @statickeywords[key] = hsh
    }
    
    # then scan for non DB files, and convert/import them and delete
    Dir["#{@bot.botclass}/keywords/*"].each {|f|
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
    if File.exist?("#{@bot.botclass}/keywords.db")
      log "upgrading old keywords (rbot 0.9.5 or prior) database format"
      old = BDB::Hash.open "#{@bot.botclass}/keywords.db", nil, 
                           "r+", 0600
      old.each {|k,v|
        @keywords[k] = v
      }
      old.close
      @keywords.flush
      File.rename("#{@bot.botclass}/keywords.db", "#{@bot.botclass}/keywords.db.old")
    end
  
    if File.exist?("#{@bot.botclass}/keyword.db")
      log "upgrading old keywords (rbot 0.9.9 or prior) database format"
      old = BDB::CIBtree.open "#{@bot.botclass}/keyword.db", nil, 
                           "r+", 0600
      old.each {|k,v|
        @keywords[k] = v
      }
      old.close
      @keywords.flush
      File.rename("#{@bot.botclass}/keyword.db", "#{@bot.botclass}/keyword.db.old")
    end
  end

  # save dynamic keywords to file
  def save
    @keywords.flush
  end
  def oldsave
    File.open("#{@bot.botclass}/keywords.rbot", "w") do |file|
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

  # m::     PrivMessage containing message info
  # key::   key being queried
  # dunno:: optional, if true, reply "dunno" if +key+ not found
  # 
  # handle a message asking about a keyword
  def keyword(m, key, dunno=true)
    return if key.nil?
     unless(kw = self[key])
       m.reply @bot.lang.get("dunno") if (dunno)
       return
     end
     response = kw.to_s
     response.gsub!(/<who>/, m.sourcenick)
     if(response =~ /^<reply>\s*(.*)/)
       m.reply "#$1"
     elsif(response =~ /^<action>\s*(.*)/)
       @bot.action m.replyto, "#$1"
     elsif(m.public? && response =~ /^<topic>\s*(.*)/)
       topic = $1
       @bot.topic m.target, topic
     else
       m.reply "#{key} #{kw.type} #{response}"
     end
  end

  
  # handle a message which alters a keyword
  # like "foo is bar", or "no, foo is baz", or "foo is also qux"
  def keyword_command(sourcenick, target, lhs, mhs, rhs, quiet=false)
    debug "got keyword command #{lhs}, #{mhs}, #{rhs}"
    overwrite = false
    overwrite = true if(lhs.gsub!(/^no,\s*/, ""))
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
      @bot.okay target if !quiet
    elsif(has_key?(lhs))
      kw = self[lhs]
      @bot.say target, "but #{lhs} #{kw.type} #{kw.desc}" if kw && !quiet
    end
  end

  # return help string for Keywords with option topic +topic+
  def help(plugin, topic="")
    case topic
      when "overview"
        return "set: <keyword> is <definition>, overide: no, <keyword> is <definition>, add to definition: <keyword> is also <definition>, random responses: <keyword> is <definition> | <definition> [| ...], plurals: <keyword> are <definition>, escaping: \\is, \\are, \\|, specials: <reply>, <action>, <who>"
      when "set"
        return "set => <keyword> is <definition>"
      when "plurals"
        return "plurals => <keywords> are <definition>"
      when "override"
        return "overide => no, <keyword> is <definition>"
      when "also"
        return "also => <keyword> is also <definition>"
      when "random"
        return "random responses => <keyword> is <definition> | <definition> [| ...]"
      when "get"
        return "asking for keywords => (with addressing) \"<keyword>?\", (without addressing) \"'<keyword>\""
      when "tell"
        return "tell <nick> about <keyword> => if <keyword> is known, tell <nick>, via /msg, its definition"
      when "forget"
        return "forget <keyword> => forget fact <keyword>"
      when "keywords"
        return "keywords => show current keyword counts"
      when "<reply>"
        return "<reply> => normal response is \"<keyword> is <definition>\", but if <definition> begins with <reply>, the response will be \"<definition>\""
      when "<action>"
        return "<action> => makes keyword respnse \"/me <definition>\""
      when "<who>"
        return "<who> => replaced with questioner in reply"
      when "<topic>"
        return "<topic> => respond by setting the topic to the rest of the definition"
      when "search"
        return "keywords search [--all] [--full] <regexp> => search keywords for <regexp>. If --all is set, search static keywords too, if --full is set, search definitions too."
      else
        return "Keyword module (Fact learning and regurgitation) topics: overview, set, plurals, override, also, random, get, tell, forget, keywords, keywords search, <reply>, <action>, <who>, <topic>"
    end
  end

  # handle a message asking the bot to tell someone about a keyword
  def keyword_tell(m, param)
    target = param[:target]
    key = nil

    # extract the keyword from the message, because unfortunately
    # the message mapper doesn't preserve whtiespace
    if m.message =~ /about\s+(.+)$/
      key = $1
    end

    unless(kw = self[key])
      m.reply @bot.lang.get("dunno_about_X") % key
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
  def keyword_stats(m, param)
    length = 0
    @statickeywords.each {|k,v|
      length += v.length
    }
    m.reply "There are currently #{@keywords.length} keywords, #{length} static facts defined."
  end

  # search for keywords, optionally also the definition and the static keywords
  def keyword_search(m, param)
    str = param[:pattern]
    all = (param[:all] == '--all')
    full = (param[:full] == '--full')
    
    begin
      re = Regexp.new(str, Regexp::IGNORECASE)
      if(@bot.auth.allow?("keyword", m.source, m.replyto))
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
          i = 0
          matches.each {|rkw|
            m.reply "[#{i+1}/#{matches.length}] #{rkw[0]} #{rkw[1].type} #{rkw[1].desc}"
            i += 1
            break if i == 3
          }
        else
          m.reply "no keywords match #{str}"
        end
      end
    rescue RegexpError => e
      m.reply "no keywords match #{str}: #{e}"
    rescue
      debug e.inspect
      m.reply "no keywords match #{str}: an error occurred"
    end
  end

  # forget one of the dynamic keywords
  def keyword_forget(m, param)
    key = param[:key]
    if(@keywords.has_key?(key))
      @keywords.delete(key)
      @bot.okay m.replyto
    end
  end

  # privmsg handler
  def listen(m)
    return if m.replied?
    if(m.address?)
      if(!(m.message =~ /\\\?\s*$/) && m.message =~ /^(.*\S)\s*\?\s*$/)
        keyword m, $1 if(@bot.auth.allow?("keyword", m.source, m.replyto))
      elsif(m.message =~ /^(.*?)\s+(is|are)\s+(.*)$/)
        keyword_command(m.sourcenick, m.replyto, $1, $2, $3) if(@bot.auth.allow?("keycmd", m.source, m.replyto))
      end
    else
      # in channel message, not to me
      # TODO option to do if(m.message =~ /^(.*)$/, ie try any line as a
      # keyword lookup.
      if(m.message =~ /^'(.*)$/ || (!@bot.config["keyword.address"] && m.message =~ /^(.*\S)\s*\?\s*$/))
        keyword m, $1, false if(@bot.auth.allow?("keyword", m.source))
      elsif(@bot.config["keyword.listen"] == true && (m.message =~ /^(.*?)\s+(is|are)\s+(.*)$/))
        # TODO MUCH more selective on what's allowed here
        keyword_command(m.sourcenick, m.replyto, $1, $2, $3, true) if(@bot.auth.allow?("keycmd", m.source))
      end
    end
  end
end

plugin = Keywords.new

plugin.map 'keyword stats', :action => 'keyword_stats'

plugin.map 'keyword search :all :full :pattern', :action => 'keyword_search',
           :defaults => {:all => '', :full => ''},
           :requirements => {:all => '--all', :full => '--full'}
           
plugin.map 'keyword forget :key', :action => 'keyword_forget'
plugin.map 'forget :key', :action => 'keyword_forget', :auth => 'keycmd'

plugin.map 'keyword tell :target about *keyword', :action => 'keyword_tell'
plugin.map 'tell :target about *keyword', :action => 'keyword_tell', :auth => 'keyword'
