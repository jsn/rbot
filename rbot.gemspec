Gem::Specification.new do |s|
  s.name = 'rbot'
  s.version = '0.9.14'
  s.summary = <<-EOF
    A modular ruby IRC bot.
  EOF
  s.description = <<-EOF
    A modular ruby IRC bot specifically designed for ease of extension via plugins.
  EOF
  s.requirements << 'Ruby, version 1.8.0 (or newer)'

  s.files = Dir[
	  'lib/**/*.rb',
	  'bin/*',
	  'data/rbot/**/*',
	  'AUTHORS',
	  'COPYING',
	  'README',
	  'REQUIREMENTS',
	  'TODO',
	  'ChangeLog',
	  'INSTALL',
	  'Usage_en.txt',
	  'setup.rb',
	  'launch_here.rb',
	  'po/*.pot',
	  'po/**/*.po'
  ]

  s.bindir = 'bin'
  s.executables = ['rbot', 'rbot-remote']
  s.default_executable = 'rbot'
  s.extensions = 'Rakefile'

#  s.autorequire = 'rbot/ircbot'
  s.has_rdoc = true
  s.rdoc_options = ['--exclude', 'post-install.rb',
  '--title', 'rbot API Documentation', '--main', 'README', 'README']

  s.author = 'Tom Gilbert'
  s.email = 'tom@linuxbrit.co.uk'
  s.homepage = 'http://ruby-rbot.org'
  s.rubyforge_project = 'rbot'
end

