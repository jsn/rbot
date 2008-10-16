#!/usr/bin/ruby
#
# Load rbot from this directory. (No need to install it with setup.rb)
#

SCM_DIR = File.expand_path File.dirname(__FILE__)
puts "Running from #{SCM_DIR}"

$:.unshift File.join(SCM_DIR, 'lib')

$version = 'rbot-0.9.14'

pwd = Dir.pwd
begin
  Dir.chdir SCM_DIR

  if File.exists? '.git'
    begin
      git_out = `git status`
      git_out.match(/^# On branch (.*)\n/)
      if $1 # git 1.5.x
        branch = $1.dup || "unknown"
        changed = git_out.match(/^# Change(.*)\n/)
        rev = "revision "
        git_out = `git log -1 --pretty=format:"%h%n%b%n%ct"`.split("\n")
        rev << git_out.first
        $version_timestamp = git_out.last.to_i
        rev << "(svn #{$1})" if git_out[1].match(/^git-svn-id: \S+@(\d+)/)
        rev << ", local changes" if changed
      else # older gits
        git_out = `git branch`
        git_out.match(/^\* (.*)\n/)
        branch = $1.dup rescue "unknown"
        rev = "revision " + `git rev-parse HEAD`[0,6]
      end
    rescue => e
      puts e.inspect
      branch = "unknown branch"
      rev = "unknown revision"
    end
    $version << " (#{branch} branch, #{rev})"
  elsif File.directory? File.join(SCM_DIR, '.svn')
    rev = " (unknown revision)"
    begin
      svn_out = `svn info`
      rev = " (revision #{$1}" if svn_out =~ /Last Changed Rev: (\d+)/
      svn_st = `svn st #{SCM_DIR}`
      rev << ", local changes" if svn_st =~ /^[MDA] /
      rev << ")"
    rescue => e
      puts e.inspect
    end
    $version += rev
  end
ensure
  Dir.chdir pwd
end

module Irc
class Bot
  module Config
    @@datadir = File.join SCM_DIR, 'data/rbot'
    @@coredir = File.join SCM_DIR, 'lib/rbot/core'
  end
end
end

load File.join(SCM_DIR, 'bin/rbot')
