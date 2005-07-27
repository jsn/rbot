# write out our datadir so we can reference it at runtime
File.open('rbotconfig.rb', "w") {|f|
  f.puts "module Irc"
  f.puts "  module Config"
  f.puts "    DATADIR = '#{config('datadir')}'"
  f.puts "  end"
  f.puts "end"
}
