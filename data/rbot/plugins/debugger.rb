# Debugging/profiling for rbot
#
# (c) 2006 Giuseppe Bilotta <giuseppe.bilotta@gmail.com>
# Licensed under GPL V2.

class DebugPlugin < Plugin
  BotConfig.register BotConfigIntegerValue.new('debug.interval',
    :default => 10, :validate => Proc.new{|v| v > 0},
    :desc => "Number of seconds between memory profile dumps")
  BotConfig.register BotConfigBooleanValue.new('debug.dump_strings',
    :default => false,
    :desc => "Set to true if you want the profiler to dump strings, false otherwise")
  BotConfig.register BotConfigStringValue.new('debug.logdir',
    :default => "",
    :desc => "Directory where profile/string dumps are to be stored")

  def initialize
    super
    @prev = Hash.new(0)
    @curr = Hash.new(0)
    @delta = Hash.new(0)
    @file = File.open("#{@bot.botclass}/#{@bot.config['debug.logdir']}/memory_profiler.log",'w')
    @thread = @bot.timer.add(@bot.config['debug.interval']) {
        begin
          GC.start
          @curr.clear

          curr_strings = []

          ObjectSpace.each_object do |o|
            @curr[o.class] += 1 #Marshal.dump(o).size rescue 1
            if @bot.config['debug.dump_strings'] and o.class == String
              curr_strings.push o
            end
          end

          if @bot.config['debug.dump_strings']
            File.open("#{@bot.botclass}/#{@bot.config['debug.logdir']}/memory_profiler_strings.log.#{Time.now.to_i}",'w') do |f|
              curr_strings.sort.each do |s|
                f.puts s
              end
            end
            curr_strings.clear
          end

          @delta.clear
          (@curr.keys + @delta.keys).uniq.each do |k,v|
            @delta[k] = @curr[k]-@prev[k]
          end

          @file.puts "Top 20"
          @delta.sort_by { |k,v| -v.abs }[0..19].sort_by { |k,v| -v}.each do |k,v|
            @file.printf "%+5d: %s (%d)\n", v, k.name, @curr[k] unless v == 0
          end
          @file.flush

          @delta.clear
          @prev.clear
          @prev.update @curr
          GC.start
        rescue Exception => err
          error "** memory_profiler error: #{err}"
        end
    }
    @bot.timer.block(@thread)
  end

  def help( plugin, topic="" )
      "debug start => start the periodic profiler; " + \
      "debug stop => stops the periodic profiler; " + \
      "debug dumpstrings => dump all of the strings"
  end

  def start_it(m, params)
    begin
      @bot.timer.unblock(@thread)
      m.reply "profile dump started"
    rescue Exception => err
      m.reply "couldn't start profile dump"
      error "couldn't start profile dump: #{err}"
    end
  end

  def stop_it(m, params)
    begin
      @bot.timer.block(@thread)
      m.reply "profile dump stop"
    rescue Exception => err
      m.reply "couldn't stop profile dump"
      error "couldn't stop profile dump: #{err}"
    end
  end

  def dump_strings(m, params)
    curr_strings = []

    m.reply "Dumping strings ..."
    begin
      GC.start
      ObjectSpace.each_object do |o|
        if o.class == String
          curr_strings.push o
        end
      end

      File.open("#{@bot.botclass}/#{@bot.config['debug.logdir']}/memory_profiler_strings.log.#{Time.now.to_i}",'w') do |f|
        curr_strings.sort.each do |s|
          f.puts s
        end
      end
      GC.start
      m.reply "... done"
    rescue Exception => err
      m.reply "dumping strings failed"
      error "dumping strings failed: #{err}"
    end
  end

end


plugin = DebugPlugin.new

plugin.default_auth( 'start', false )
plugin.default_auth( 'stop', false )
plugin.default_auth( 'dumpstrings', false )

plugin.map 'debug start', :action => 'start_it'
plugin.map 'debug stop', :action => 'stop_it'
plugin.map 'debug dumpstrings', :action => 'dump_strings'


