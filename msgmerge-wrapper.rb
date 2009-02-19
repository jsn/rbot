#!/usr/bin/ruby
# This is a wrapper to msgmerge, it executes msgmerge with the given arguments, and
# if msgmerge output is empty, prints the content of the file named the first
# argument. otherwise it prints the output of msgmerge. The wrapper should be
# "compatible" with the real msgmerge if msgmerge output is non-empty, or if the
# first argument is the defpo file (instead of an option, or --)
#
# The path to msgmerge can be specified in env variable REAL_MSGMERGE_PATH
#
# The purpose is to provide a workaround for ruby-gettext, which treats empty output
# from msgmerge as error in the po file, where it should mean that no modification
# is needed to the defpo. For updates on the issue follow
# http://rubyforge.org/pipermail/gettext-users-en/2008-June/000094.html


msgmerge = ENV['REAL_MSGMERGE_PATH'] || 'msgmerge'
defpo = ARGV.shift
output = `#{msgmerge} #{defpo} #{ARGV.join ' '}`
output = File.read(defpo) if output.empty?
STDOUT.write output

