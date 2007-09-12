#!/usr/bin/ruby
#
# Load rbot from this directory. (No need to install it with setup.rb)
#

SVN_DIR = File.expand_path(File.dirname('__FILE__'))
puts "Running from #{SVN_DIR}"

$:.unshift File.join(SVN_DIR, 'lib')

module Irc
class Bot
  module Config
    @@datadir = File.join SVN_DIR, 'data/rbot'
    @@coredir = File.join SVN_DIR, 'lib/rbot/core'
  end
end
end

load File.join(SVN_DIR, 'bin/rbot')
