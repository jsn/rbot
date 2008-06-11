#!/usr/bin/ruby
#
# Load rbot from this directory. (No need to install it with setup.rb)
#

SCM_DIR = File.expand_path File.dirname(__FILE__)

Dir.chdir SCM_DIR

puts "Running from #{SCM_DIR}"

$:.unshift File.join(SCM_DIR, 'lib')

module Irc
class Bot
  module Config
    @@datadir = File.join SCM_DIR, 'data/rbot'
    @@coredir = File.join SCM_DIR, 'lib/rbot/core'
  end
end
end

load File.join(SCM_DIR, 'bin/rbot')
