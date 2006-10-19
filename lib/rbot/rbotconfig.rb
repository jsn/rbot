module Irc
  module Config
    unless defined?(@@datadir)
      @@datadir = nil

      defaultdatadir = File.expand_path(File.dirname($0) + '/../data/rbot')

      if File.directory? defaultdatadir
        @@datadir = defaultdatadir
      end
    end

    unless defined?(@@coredir)
      @@coredir = nil

      defaultcoredir = File.expand_path(File.dirname($0) + '/../lib/rbot/core')

      if File.directory? defaultcoredir
        @@coredir = defaultcoredir
      end
    end

    # setup pkg-based configuration - i.e. where were we installed to, where
    # are our data files, etc.
    if @@datadir.nil? or @@coredir.nil?
      begin
        debug "trying to load rubygems"
        require 'rubygems'
        debug "loaded rubygems, looking for rbot-#$version"
        if $version =~ /(.*)-svn\Z/
          version = $1
        else
          version = $version
        end
        gemname, gem = Gem.source_index.find{|name, spec| spec.name == 'rbot' && spec.version.version == version}
        debug "got gem #{gem}"
        if gem && path = gem.full_gem_path
          debug "installed via rubygems to #{path}"
          @@datadir = "#{path}/data/rbot"
          @@coredir = "#{path}/lib/rbot/core"
        else
          debug "not installed via rubygems"
        end
      rescue LoadError,NameError,NoMethodError
        debug "no rubygems installed"
      end
    end

    if @@datadir.nil? or @@coredir.nil?
      begin
        require 'rbot/pkgconfig'
        @@datadir = PKGConfig::DATADIR
        @@coredir = PKGConfig::COREDIR
      rescue LoadError
        error "fatal - no way to determine data or core dir"
        exit 2
      end
    end

    def Config.datadir
      @@datadir
    end

    def Config.coredir
      @@coredir
    end
  end
end
