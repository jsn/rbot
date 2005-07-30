module Irc

  class Language
    BotConfig.register('core.language', 
      :default => "english", :type => :enum,
      :values => Dir.new(Config::DATADIR + "/languages").collect {|f|
                   f =~ /\.lang$/ ? f.gsub(/\.lang$/, "") : nil
                 }.compact,   
      :desc => "Which language file the bot should use")
    
    def initialize(language, file="")
      @language = language
      if file.empty?
        file = Config::DATADIR + "/languages/#{@language}.lang"
      end
      unless(FileTest.exist?(file))
        raise "no such language: #{@language} (no such file #{file})"
      end
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
