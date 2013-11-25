#-- vim:sw=2:et
#++
#
# :title: Language module for rbot
#
# This module takes care of language handling for rbot:
# setting the core.language value, loading the appropriate
# .lang file etc.

module Irc
class Bot
  class Language

    # This constant hash holds the mapping
    # from long language names to the usual POSIX
    # locale specifications
    Lang2Locale = {
      :english  => 'en',
      :british_english  => 'en_GB',
      :american_english  => 'en_US',
      :italian  => 'it',
      :french   => 'fr',
      :german   => 'de',
      :dutch    => 'nl',
      :japanese => 'ja',
      :russian  => 'ru',
      :finnish  => 'fi',
      :traditional_chinese => 'zh_TW',
      :simplified_chinese => 'zh_CN'
    }
    # On WIN32 it appears necessary to have ".UTF-8" explicitly for gettext to use UTF-8
    Lang2Locale.each_value {|v| v.replace(v + '.UTF-8')}

    # Return the shortest language for the current
    # GetText locale
    def Language.from_locale
      return 'english' unless defined?(GetText)
      lang = locale.language
      if locale.country
        str = lang + "_#{locale.country}"
        if Lang2Locale.value?(str)
          # Get the shortest key in Lang2Locale which maps to the given lang_country
          lang_str = Lang2Locale.select { |k, v| v == str }.transpose.first.map { |v| v.to_s }.sort { |a, b| a.length <=> b.length }.first
          if File.exist?(File.join(Config::datadir, "languages/#{lang_str}.lang"))
            return lang_str
          end
        end
      end
      # lang_country didn't work, let's try lan
      if Lang2Locale.value?(lang)
        # Get the shortest key in Lang2Locale which maps to the given lang
        lang_str = Lang2Locale.select { |k, v| v == lang }.transpose.first.map { |v| v.to_s }.sort { |a, b| a.length <=> b.length }.first
        if File.exist?(File.join(Config::datadir, "/languages/#{lang_str}.lang"))
          return lang_str
        end
      end
      # all else fail, return 'english'
      return 'english'
    end

    Config.register Config::EnumValue.new('core.language',
      :default => Irc::Bot::Language.from_locale, :wizard => true,
      :values => Proc.new{|bot|
            Dir.new(Config::datadir + "/languages").collect {|f|
              f =~ /\.lang$/ ? f.gsub(/\.lang$/, "") : nil
            }.compact
          },
      :on_change => Proc.new {|bot, v| bot.lang.set_language v},
      :desc => "Which language file the bot should use")

    def initialize(bot, language)
      @bot = bot
      set_language language
    end
    attr_reader :language

    def set_language(language)
      lang_str = language.to_s.downcase.gsub(/\s+/,'_')
      lang_sym = lang_str.intern
      if defined?(GetText) and Lang2Locale.key?(lang_sym)
        GetText.set_locale(Lang2Locale[lang_sym])
        debug "locale set to #{locale}"
        rbot_gettext_debug
      else
        warning "Unable to set locale, unknown language #{language} (#{lang_str})"
      end

      file = Config::datadir + "/languages/#{lang_str}.lang"
      unless(FileTest.exist?(file))
        raise "no such language: #{lang_str} (no such file #{file})"
      end
      @language = lang_str
      @file = file
      scan
      return if @bot.plugins.nil?
      @bot.plugins.core_modules.each { |p|
        if p.respond_to?('set_language')
          p.set_language(@language)
        end
      }
      @bot.plugins.plugins.each { |p|
        if p.respond_to?('set_language')
          p.set_language(@language)
        end
      }
    end

    def scan
      @strings = Hash.new
      current_key = nil
      IO.foreach(@file) {|l|
        next if l =~ /^$/
        next if l =~ /^\s*#/
        if(l =~ /^(\S+):$/)
          @strings[$1] = Array.new
          current_key = $1
        elsif(l =~ /^\s*(.*)$/)
          @strings[current_key] << $1
        end
      }
    end

    def rescan
      scan
    end

    def get(key)
      if(@strings.has_key?(key))
        return @strings[key][rand(@strings[key].length)]
      else
        raise "undefined language key"
      end
    end

    def save
      File.open(@file, "w") {|file|
        @strings.each {|key,val|
          file.puts "#{key}:"
          val.each_value {|v|
            file.puts "   #{v}"
          }
        }
      }
    end
  end

end
end
