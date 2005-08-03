module Irc
module Language

  class Language
    BotConfig.register BotConfigEnumValue.new('core.language', 
      :default => "english", :wizard => true,
      :values => Proc.new{|bot|
            Dir.new(Config::datadir + "/languages").collect {|f|
              f =~ /\.lang$/ ? f.gsub(/\.lang$/, "") : nil
            }.compact
          },   
      :on_change => Proc.new {|bot, v| bot.lang.set_language v},
      :desc => "Which language file the bot should use")
    
    def initialize(language)
      set_language language
    end

    def set_language(language)
      file = Config::datadir + "/languages/#{language}.lang"
      unless(FileTest.exist?(file))
        raise "no such language: #{language} (no such file #{file})"
      end
      @language = language
      @file = file
      scan
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
