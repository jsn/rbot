module Irc

  # container for bot configuration
  # just treat it like a hash
  class BotConfig < Hash

    # bot:: parent bot class
    # create a new config hash from #{botclass}/conf.rbot
    def initialize(bot)
      super(false)
      @bot = bot
      # some defaults
      self["SERVER"] = "localhost"
      self["PORT"] = "6667"
      self["NICK"] = "rbot"
      self["USER"] = "gilbertt"
      self["LANGUAGE"] = "english"
      self["SAVE_EVERY"] = "60"
      self["KEYWORD_LISTEN"] = false
      if(File.exist?("#{@bot.botclass}/conf.rbot"))
        IO.foreach("#{@bot.botclass}/conf.rbot") do |line|
          next if(line =~ /^\s*#/)
          if(line =~ /(\S+)\s+=\s+(.*)$/)
            self[$1] = $2 if($2)
          end
        end
      end
    end

    # write current configuration to #{botclass}/conf.rbot
    def save
      Dir.mkdir("#{@bot.botclass}") if(!File.exist?("#{@bot.botclass}"))
      File.open("#{@bot.botclass}/conf.rbot", "w") do |file|
        self.each do |key, value|
          file.puts "#{key} = #{value}"
        end
      end
    end
  end
end
