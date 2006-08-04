# write out our datadir so we can reference it at runtime
File.open("pkgconfig.rb", "w") {|f|
  f.puts "module Irc"
  f.puts "  module PKGConfig"
  f.puts "    DATADIR = '#{config('datadir')}/rbot'"
  f.puts "    COREDIR = '#{config('rbdir')}/core'"
  f.puts "  end"
  f.puts "end"
}
