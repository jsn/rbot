#!/usr/bin/ruby
#
# Load rbot from this directory. (No need to install it with setup.rb)
#

BASEDIR = Dir.pwd

#puts "Load path: #{$LOAD_PATH.inspect}"

def add_to_path(dir)
  $LOAD_PATH.unshift dir
end

module Irc
  module PKGConfig
    DATADIR = File.join BASEDIR, 'data/rbot'
    COREDIR = File.join BASEDIR, 'lib/rbot/core'
  end
end

add_to_path( File.join BASEDIR, 'lib' )

p ARGV
ARGV << "--debug"
p ARGV

load( File.join BASEDIR, 'bin/rbot' )
