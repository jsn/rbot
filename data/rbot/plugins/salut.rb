# vim: set sw=2 et:
# Salutations plugin: respond to salutations

unless Array.respond_to?(:pick_one)
  debug "Defining the pick_one method for Array"
  class ::Array
    def pick_one
      return nil if self.empty?
      self[rand(self.length)]
    end
  end
end


class SalutPlugin < Plugin
  BotConfig.register BotConfigBooleanValue.new('salut.all_languages',
    :default => true, 
    :desc => "Check for a salutation in all languages and not just in the one defined by core.language",
    :on_change => Proc.new {|bot, v| bot.plugins['salut'].reload}
  )

  def initialize
    @salutations = Hash.new
    @match = nil
    @main_lang_str = nil
    @main_lang = nil
    @all_langs = true
    super
    reload
  end

  def set_language(what)
    reload
  end

  def create_match
    @match = Hash.new
    ar_in = Array.new
    ar_out = Array.new
    ar_both = Array.new
    @salutations.each { |lang, hash|
      hash.each { |situation, array|
        case situation.to_s
        when /in$/
          ar_in += array
        when /out$/
          ar_out += array
        else
          ar_both += array
        end
      }
    }
    @match[:in] = Regexp.new("\\b(?:" + ar_in.uniq.map { |txt|
      Regexp.escape(txt)
    }.join('|') + ")\\b", Regexp::IGNORECASE) unless ar_in.empty?
    @match[:out] = Regexp.new("\\b(?:" + ar_out.uniq.map { |txt|
      Regexp.escape(txt)
    }.join('|') + ")\\b", Regexp::IGNORECASE) unless ar_out.empty?
    @match[:both] = Regexp.new("\\b(?:" + ar_both.uniq.map { |txt|
      Regexp.escape(txt)
    }.join('|') + ")\\b", Regexp::IGNORECASE) unless ar_both.empty?
    debug "Matches: #{@match.inspect}"
  end

  def listen(m)
    salut = nil
    [:both, :in, :out].each { |k|
      next unless @match[k]
      debug "Checking salutations #{k} (#{@match[k].inspect})"
      if m.message =~ /^#{@match[k]}/
        salut = k
        break
      end
    }
    return unless salut
    h = Time.new.hour
    case h
    when 4...12
      salut_reply(m, salut, :morning)
    when 12...18
      salut_reply(m, salut, :afternoon)
    else
      salut_reply(m, salut, :evening)
    end
  end

  def salut_reply(m, k, time)
    debug "Replying to #{k} in the #{time}"
    case k
    when :both
      sfx = ""
    else
      sfx = "-#{k}"
    end
    debug "Building array ..."
    rep_ar = Array.new
    rep_ar += @salutations[@main_lang].fetch("#{time}#{sfx}".to_sym, [])
    rep_ar += @salutations[@main_lang].fetch("#{time}".to_sym, []) unless sfx.empty?
    rep_ar += @salutations[@main_lang].fetch("generic#{sfx}".to_sym, [])
    rep_ar += @salutations[@main_lang].fetch("generic".to_sym, []) unless sfx.empty?
    debug "Choosing reply in #{rep_ar.inspect} ..."
    if rep_ar.empty?
      if m.public? and (m.address? or m =~ /#{Regexp.escape(@bot.nick)}/)
        choice = @bot.lang.get("hello_X") % m.sourcenick
      else
        choice = @bot.lang.get("hello") % m.sourcenick
      end
    else
      choice = rep_ar.pick_one
      if m.public? and (m.address? or m.message =~ /#{Regexp.escape(@bot.nick)}/)
        choice += "#{[',',''].pick_one} #{m.sourcenick}"
        choice += [" :)", " :D", "!", "", "", ""].pick_one
      end
    end
    debug "Replying #{choice}"
    m.plainreply choice
  end

  def reload
    save
    @main_lang_str = @bot.config['core.language']
    @main_lang = @main_lang_str.to_sym
    @all_langs = @bot.config['salut.all_languages']
    if @all_langs
      # Get all available languages
      langs = Dir.new("#{@bot.botclass}/salut").collect {|f|
        f =~ /salut-([^.]+)/ ? $1 : nil
      }.compact
      langs.each { |lang|
        @salutations[lang.to_sym] = load_lang(lang)
      }
    else
      @salutations.clear
      @salutations[@main_lang] = load_lang(@main_lang_str)
    end
    create_match
  end

  def load_lang(lang)
    dir = "#{@bot.botclass}/salut"
    if not File.exist?(dir)
      Dir.mkdir(dir)
    end
    file = "#{@bot.botclass}/salut/salut-#{lang}"
    if File.exist?(file)
      begin
        salutations = Hash.new
        content = YAML::load_file(file)
        content.each { |key, val|
          salutations[key.to_sym] = val
        }
        return salutations
      rescue
        error "failed to read salutations in #{lang}: #{$!}"
      end
    end
    return nil
  end

  def save
    return if @salutations.empty?
    @salutations.each { |lang, val|
      l = lang.to_s
      save_lang(lang, val)
    }
  end

  def save_lang(lang, val)
    file = "#{@bot.botclass}/salut/salut-#{lang}"
    Utils.safe_save(file) { |file|
      file.puts val.to_yaml
    }
  end

end

plugin = SalutPlugin.new

