require 'rubygems'

spec = Gem::Specification.new do |s|

  #### Basic information.

  s.name = 'rbot'
  s.version = '0.9.9'
  s.summary = <<-EOF
    A modular ruby IRC bot.
  EOF
  s.description = <<-EOF
    A modular ruby IRC bot specifically designed for ease of extension via plugins.
  EOF

  s.requirements << 'Ruby, version 1.8.0 (or newer)'

  #### Which files are to be included in this gem?  Everything!  (Except .svn directories.)

  s.files = Dir.glob("**/*").delete_if { |item| item.include?(".svn") }

  #### C code extensions.

  # s.require_path = '.' # is this correct?
  # s.extensions << "extconf.rb"

  #### Load-time details: library and application (you will need one or both).
  s.autorequire = 'rbot/ircbot'
  s.has_rdoc = true
  s.rdoc_options = ['--include', 'lib', '--exclude',
  '(post-config.rb|rbotconfig.rb)', '--title', 'rbot API Documentation',
  '--main', 'lib/rbot/ircbot.rb', 'lib', 'bin/rbot']

  #### Author and project details.

  s.author = 'Tom Gilbert'
  s.email = 'tom@linuxbrit.co.uk'
  s.homepage = 'http://linuxbrit.co.uk/rbot/'
  s.rubyforge_project = 'rbot'
end
