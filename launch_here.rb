#!/usr/bin/ruby
#
# Load rbot from this directory. (No need to install it with setup.rb)
#

SCM_DIR = File.expand_path File.dirname(__FILE__)
puts "Running from #{SCM_DIR}"

$:.unshift File.join(SCM_DIR, 'lib')

$version = '0.9.15-git'

pwd = Dir.pwd
begin
  Dir.chdir SCM_DIR

  if File.exists? '.git'
    begin
      git_out = `git log -1 --pretty=raw | git name-rev --stdin`.split("\n")
      commit, branch_spec = git_out.first.scan(/^commit (\S+)(?: \((\S+)\))?$/).first
      $version_timestamp = git_out[4].split[-2].to_i
      subject = git_out[6].strip rescue ""
      subject[77..-1] = "..." if subject.length > 80
      rev = "revision #{commit[0,7]}"
      rev << " [#{subject}]" unless subject.empty?
      changes = `git diff-index --stat HEAD`.split("\n").last.split(", ").first rescue nil
      rev << ", #{changes.strip}" if changes
      if branch_spec
        tag, branch, offset = branch_spec.scan(/^(?:(tag)s\/)?(\S+?)(?:^0)?(?:~(\d+))?$/).first
        tag ||= "branch"
        branch << " #{tag}"
        branch << "-#{offset}" if offset
      else
        branch = "unknown branch"
      end
    rescue => e
      puts e.inspect
      branch = "unknown branch"
      rev = "unknown revision"
    end
    $version << " (#{branch}, #{rev})"
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
