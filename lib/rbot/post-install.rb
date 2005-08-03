# write out our datadir so we can reference it at runtime
File.open("#{config('rbdir')}/rbot/pkgconfig.rb", "w") {|f|
  f.puts "module Irc"
  f.puts "  module PKGConfig"
  f.puts "    DATADIR = '#{config('datadir')}/rbot'"
  f.puts "  end"
  f.puts "end"
}
