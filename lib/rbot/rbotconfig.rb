module Irc
  module Config
    @@datadir = nil
    # setup pkg-based configuration - i.e. where were we installed to, where
    # are our data files, etc.
    begin
      require 'rubygems'
      gemname, gem = Gem.source_index.find{|name, spec| spec.name == 'rbot' && spec.version.version == $version}
      if gem && path = gem.full_gem_path
        debug "installed via rubygems to #{path}"
        @@datadir = "#{path}/data/rbot"
      else
        debug "not installed via rubygems"
      end
    rescue LoadError
      debug "no rubygems installed"
    end

    if @@datadir.nil?
      begin
        require 'rbot/pkgconfig'
        @@datadir = PKGConfig::DATADIR
      rescue LoadError
        puts "fatal - no way to determine data dir"
        exit 2
      end
    end
    
    def Config.datadir
      @@datadir
    end
  end
end
