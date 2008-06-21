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
  s.homepage = 'http://ruby-rbot.org'
  s.rubyforge_project = 'rbot'
end

Rake::GemPackageTask.new(spec) do |pkg|
  pkg.need_zip = true
  pkg.need_tar = true
end

PLUGIN_FILES = FileList['data/rbot/plugins/**/*.rb']
NON_PLUGIN_FILES = FileList["{lib,bin,data}/**/*.{rb,rhtml}"] - PLUGIN_FILES
rgettext_proc = proc do |t|
  require 'gettext/utils'
  plugin_files, pot_file = t.prerequisites, t.name
  GetText.rgettext(plugin_files, pot_file)
end

# generate pot file for non-plugin files
file('po/rbot.pot' => NON_PLUGIN_FILES, &rgettext_proc)

# generate pot files for plugin files
rule(%r'^po/.+\.pot$' => proc {|fn|
  PLUGIN_FILES.select {|f| f.pathmap('rbot-%n') == fn.pathmap('%n')}
}, &rgettext_proc)

# update po files
# ruby-gettext treats empty output from msgmerge as error, causing this task to
# fail. we provide a wrapper to work around it. see bin/msgmerge-wrapper.rb for
# details
ENV['REAL_MSGMERGE_PATH'] = ENV['MSGMERGE_PATH']
ENV['MSGMERGE_PATH'] = ENV['MSGMERGE_WRAPPER_PATH'] || 'ruby msgmerge-wrapper.rb'
rule(%r'^po/.+/.+\.po$' => proc {|fn| fn.pathmap '%{^po/.+/,po/}X.pot'}) do |t|
  require 'gettext/utils'
  po_file, pot_file = t.name, t.source
  GetText.msgmerge po_file, pot_file, 'rbot'
end

# generate mo files
rule(%r'^data/locale/.+/LC_MESSAGES/.+\.mo$' => proc {|fn|
  [ fn.pathmap('%{^data/locale,po;LC_MESSAGES/,}X.po'), 
    # the directory is created if not existing
    fn.pathmap('%d') ]
}) do |t|
  po_file, mo_file = t.source, t.name
  require 'gettext/utils'
  GetText.rmsgfmt po_file, mo_file
end

PLUGIN_BASENAMES = PLUGIN_FILES.map {|f| f.pathmap('%n')}
LOCALES = FileList['po/*/'].map {|d| d.pathmap('%n')}

LOCALES.each do |l|
  directory "data/locale/#{l}/LC_MESSAGES"
end

desc 'Update po files'
task :updatepo => LOCALES.map {|l|
  ["po/#{l}/rbot.po"] +
  PLUGIN_BASENAMES.map {|n| "po/#{l}/rbot-#{n}.po"}
}.flatten

desc 'Generate mo files'
task :makemo => LOCALES.map {|l|
  ["data/locale/#{l}/LC_MESSAGES/rbot.mo"] +
  PLUGIN_BASENAMES.map {|n| "data/locale/#{l}/LC_MESSAGES/rbot-#{n}.mo"}
}.flatten

