require 'rubygems'
require 'rake'
require 'rake/gempackagetask'

task :default => [:repackage]

spec = Gem::Specification.new do |s|
  s.name = 'rbot'
  s.version = '0.9.11'
  s.summary = <<-EOF
    A modular ruby IRC bot.
  EOF
  s.description = <<-EOF
    A modular ruby IRC bot specifically designed for ease of extension via plugins.
  EOF
  s.requirements << 'Ruby, version 1.8.0 (or newer)'

  #  s.files = Dir.glob("**/*").delete_if { |item| item.include?(".svn") }
  s.files = FileList['lib/**/*.rb', 'bin/*', 'data/**/*', 'AUTHORS', 'COPYING', 'README', 'REQUIREMENTS', 'TODO', 'ChangeLog', 'INSTALL',  'Usage_en.txt', 'setup.rb'].to_a.delete_if {|item| item == ".svn"}
  s.executables << 'rbot'

#  s.autorequire = 'rbot/ircbot'
  s.has_rdoc = true
  s.rdoc_options = ['--exclude', 'post-install.rb',
  '--title', 'rbot API Documentation', '--main', 'README', 'README']

  s.author = 'Tom Gilbert'
  s.email = 'tom@linuxbrit.co.uk'
  s.homepage = 'http://linuxbrit.co.uk/rbot/'
  s.rubyforge_project = 'rbot'
end

Rake::GemPackageTask.new(spec) do |pkg|
  pkg.need_zip = true
  pkg.need_tar = true
end

desc "Update pot/po files."
task :updatepo do
  require 'gettext/utils'
  GetText.update_pofiles("rbot", Dir.glob("{lib,bin,data}/**/*.{rb,rhtml}"), "rbot")
end

desc "Create mo-files"
task :makemo do
  require 'gettext/utils'
  GetText.create_mofiles(true)
end
