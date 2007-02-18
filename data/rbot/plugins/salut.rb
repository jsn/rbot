#-- vim:sw=2:et
#++
#
# :title: Salutations plugin for rbot
#
# Author:: Giuseppe "Oblomov" Bilotta <giuseppe.bilotta@gmail.com>
# Copyright:: (C) 2006-2007 Giuseppe Bilotta
# License:: GPL v2
#
# Salutations plugin: respond to salutations
#
# TODO:: allow online editing of salutations
#
# TODO:: *REMEMBER* to set @changed to true after edit or changes won't be saved

class SalutPlugin < Plugin
  BotConfig.register BotConfigBooleanValue.new('salut.all_languages',
    :default => true, 
    :desc => "Check for a salutation in all languages and not just in the one defined by core.language",
    :on_change => Proc.new {|bot, v| bot.plugins['salut'].reload}
  )
  BotConfig.register BotConfigBooleanValue.new('salut.address_only',
    :default => true, 
    :desc => "When set to true, the bot will only reply to salutations directed at him",
    :on_change => Proc.new {|bot, v| bot.plugins['salut'].reload}
  )


  def initialize
    @salutations = Hash.new
    @match = Hash.new
    @match_langs = Array.new
    @main_lang_str = nil
    @main_lang = nil
    @all_langs = true
    @changed = false
    super
    reload
  end

  def set_language(what)
    reload
  end

  def create_match
    @match.clear
    ar_dest = Array.new
    ar_in = Array.new
    ar_out = Array.new
    ar_both = Array.new
    @salutations.each { |lang, hash|
      ar_dest.clear
      ar_in.clear
      ar_out.clear
      ar_both.clear
      hash.each { |situation, array|
        case situation.to_s
        when /^generic-dest$/
          ar_dest += array
        when /in$/
          ar_in += array
        when /out$/
          ar_out += array
        else
          ar_both += array
        end
      }
      @match[lang] = Hash.new
      @match[lang][:in] = Regexp.new("\\b(?:" + ar_in.uniq.map { |txt|
        Regexp.escape(txt)
      }.join('|') + ")\\b", Regexp::IGNORECASE) unless ar_in.empty?
      @match[lang][:out] = Regexp.new("\\b(?:" + ar_out.uniq.map { |txt|
        Regexp.escape(txt)
      }.join('|') + ")\\b", Regexp::IGNORECASE) unless ar_out.empty?
      @match[lang][:both] = Regexp.new("\\b(?:" + ar_both.uniq.map { |txt|
        Regexp.escape(txt)
      }.join('|') + ")\\b", Regexp::IGNORECASE) unless ar_both.empty?
      @match[lang][:dest] = Regexp.new("\\b(?:" + ar_dest.uniq.map { |txt|
        Regexp.escape(txt)
      }.join('|') + ")\\b", Regexp::IGNORECASE) unless ar_dest.empty?
    }
    @punct = /\s*[.,:!;?]?\s*/ # Punctuation

    # Languages to match for, in order
    @match_langs.clear
    @match_langs << @main_lang if @match.key?(@main_lang)
    @match_langs << :english if @match.key?(:english)
    @match.each_key { |key|
      @match_langs << key
    }
    @match_langs.uniq!
  end

  def listen(m)
    return if @match.empty?
    return unless m.kind_of?(PrivMessage)
    return if m.address? and m.plugin == 'config'
    to_me = m.address? || m.message =~ /#{Regexp.escape(@bot.nick)}/i
    if @bot.config['salut.address_only']
      return unless to_me
    end
    salut = nil
    @match_langs.each { |lang|
      [:both, :in, :out].each { |k|
        next unless @match[lang][k]
        if m.message =~ @match[lang][k]
          salut = [@match[lang][k], lang, k]
          break
        end
      }
      break if salut
    }
    return unless salut
    # If the bot wasn't addressed, we continue only if the match was exact
    # (apart from space and punctuation) or if @match[:dest] matches too
    return unless to_me or m.message =~ /^#{@punct}#{salut.first}#{@punct}$/ or m.message =~ @match[salut[1]][:dest] 
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

  def salut_reply(m, salut, time)
    lang = salut[1]
    k = salut[2]
    debug "Replying to #{salut.first} (#{lang} #{k}) in the #{time}"
    # salut_ar = @salutations[@main_lang].update @salutations[:english].update @salutations[lang]
    salut_ar = @salutations[lang]
    case k
    when :both
      sfx = ""
    else
      sfx = "-#{k}"
    end
    debug "Building array ..."
    rep_ar = Array.new
    rep_ar += salut_ar.fetch("#{time}#{sfx}".to_sym, [])
    rep_ar += salut_ar.fetch("#{time}".to_sym, []) unless sfx.empty?
    rep_ar += salut_ar.fetch("generic#{sfx}".to_sym, [])
    rep_ar += salut_ar.fetch("generic".to_sym, []) unless sfx.empty?
    debug "Choosing reply in #{rep_ar.inspect} ..."
    if rep_ar.empty?
      if m.public? # and (m.address? or m =~ /#{Regexp.escape(@bot.nick)}/)
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
    @changed = false
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
    return unless @changed
    @salutations.each { |lang, val|
      l = lang.to_s
      save_lang(lang, val)
    }
    @changed = false
  end

  def save_lang(lang, val)
    fn = "#{@bot.botclass}/salut/salut-#{lang}"
    Utils.safe_save(fn) { |file|
      file.puts val.to_yaml
    }
  end

end

plugin = SalutPlugin.new

