#-- vim:sw=2:et
#++
#
# :title: GetText interface for rbot
#
# Load gettext module and provide fallback in case of failure

class GetTextVersionError < Exception
end

# try to load gettext, or provide fake getttext functions
begin
# workaround for gettext not checking empty LANGUAGE
if ENV["LANGUAGE"] and ENV["LANGUAGE"].empty?
  ENV.delete "LANGUAGE"
end

  require 'gettext/version'

  gettext_version = GetText::VERSION.split('.').map {|n| n.to_i}
  class ::Array
    include Comparable # for Array#>=
  end
  unless gettext_version >= [1, 8, 0]
    raise GetTextVersionError, "Unsupported ruby-gettext version installed: #{gettext_version.join '.'}; supported versions are 1.8.0 and above"
  end

  require 'gettext'

  include GetText

  rbot_locale_path = File.join(Irc::Bot::Config.datadir,
    gettext_version < [2, 2, 0] ?
      "../locale/%{locale}/LC_MESSAGES/%{name}.mo" :
      "../locale/%{lang}/LC_MESSAGES/%{name}.mo")

  if gettext_version < [2, 0, 0]
    add_default_locale_path(rbot_locale_path)
  else
    LocalePath.add_default_rule(rbot_locale_path)
  end

  if GetText.respond_to? :cached=
    GetText.cached = false
  elsif TextDomain.respond_to? :cached=
    TextDomain.cached = false
  else
    warning 'This version of ruby-gettext does not support non-cached mode; mo files are not reloaded when setting language'
  end

  begin
    bindtextdomain 'rbot'
  rescue NoMethodError => e
    error e
    warning 'Trying to work around RubyGems/GetText incompatibility'
    module ::Gem
      def self.all_load_paths
        result = []

        Gem.path.each do |gemdir|
          each_load_path all_partials(gemdir) do |load_path|
            result << load_path
          end
        end

        result
      end
    end
    retry
  end



  module GetText
    # patch for ruby-gettext 1.x to cope with anonymous modules used by rbot.
    # bound_targets and related methods are not used nor present in 2.x, and
    # this patch is not needed
    if respond_to? :bound_targets, true
      alias :orig_bound_targets :bound_targets

      def bound_targets(*a)  # :nodoc:
        bt = orig_bound_targets(*a) rescue []
        bt.empty? ? orig_bound_targets(Object) : bt
      end
    end

    require 'stringio'

    # GetText 2.1.0 does not provide current_textdomain_info,
    # so we adapt the one from 1.9.10
    # TODO we would _really_ like to have a future-proof version of this,
    # but judging by the ruby gettext source code, this isn't going to
    # happen anytime soon.
    if not respond_to? :current_textdomain_info
      # Show the current textdomain information. This function is for debugging.
      # * options: options as a Hash.
      #   * :with_messages - show informations with messages of the current mo file. Default is false.
      #   * :out - An output target. Default is STDOUT.
      #   * :with_paths - show the load paths for mo-files.
      def current_textdomain_info(options = {})
        opts = {:with_messages => false, :with_paths => false, :out => STDOUT}.merge(options)
        ret = nil
        # this is for 2.1.0
        TextDomainManager.each_textdomains(self) {|textdomain, lang|
          opts[:out].puts "TextDomain name: #{textdomain.name.inspect}"
          opts[:out].puts "TextDomain current locale: #{lang.to_s.inspect}"
          opts[:out].puts "TextDomain current mo path: #{textdomain.instance_variable_get(:@locale_path).current_path(lang).inspect}"
          if opts[:with_paths]
            opts[:out].puts "TextDomain locale file paths:"
            textdomain.locale_paths.each do |v|
              opts[:out].puts "  #{v}"
            end
          end
          if opts[:with_messages]
            opts[:out].puts "The messages in the mo file:"
            textdomain.current_mo.each{|k, v|
              opts[:out].puts "  \"#{k}\": \"#{v}\""
            }
          end
        }
      end
    end

    # This method is used to output debug information on the GetText
    # textdomain, and it's called by the language setting routines
    # in rbot
    def rbot_gettext_debug
      begin
        gettext_info = StringIO.new
        current_textdomain_info(:out => gettext_info) # fails sometimes
      rescue Exception
        warning "failed to retrieve textdomain info. maybe an mo file doesn't exist for your locale."
        debug $!
      ensure
        gettext_info.string.each_line { |l| debug l}
      end
    end
  end

  log "gettext loaded"

rescue LoadError, GetTextVersionError
  warning "failed to load ruby-gettext package: #{$!}; translations are disabled"

  # undefine GetText, in case it got defined because the error was caused by a
  # wrong version
  if defined?(GetText)
    Object.module_eval { remove_const("GetText") }
  end

  # dummy functions that return msg_id without translation
  def _(s)
    s
  end

  def N_(s)
    s
  end

  def n_(s_single, s_plural, n)
    n > 1 ? s_plural : s_single
  end

  def Nn_(s_single, s_plural)
    n_(s_single, s_plural)
  end

  def s_(*args)
    args[0]
  end

  def bindtextdomain_to(*args)
  end

  # the following extension to String#% is from ruby-gettext's string.rb file.
  # it needs to be included in the fallback since the source already use this form

=begin
  string.rb - Extension for String.

  Copyright (C) 2005,2006 Masao Mutoh

  You may redistribute it and/or modify it under the same
  license terms as Ruby.
=end

  # Extension for String class.
  #
  # String#% method which accept "named argument". The translator can know
  # the meaning of the msgids using "named argument" instead of %s/%d style.
  class String
    alias :_old_format_m :% # :nodoc:

    # call-seq:
    #  %(arg)
    #  %(hash)
    #
    # Format - Uses str as a format specification, and returns the result of applying it to arg.
    # If the format specification contains more than one substitution, then arg must be
    # an Array containing the values to be substituted. See Kernel::sprintf for details of the
    # format string. This is the default behavior of the String class.
    # * arg: an Array or other class except Hash.
    # * Returns: formatted String
    #
    #  (e.g.) "%s, %s" % ["Masao", "Mutoh"]
    #
    # Also you can use a Hash as the "named argument". This is recommanded way for Ruby-GetText
    # because the translators can understand the meanings of the msgids easily.
    # * hash: {:key1 => value1, :key2 => value2, ... }
    # * Returns: formatted String
    #
    #  (e.g.) "%{firstname}, %{familyname}" % {:firstname => "Masao", :familyname => "Mutoh"}
    def %(args)
      if args.kind_of?(Hash)
        ret = dup
        args.each {|key, value|
          ret.gsub!(/\%\{#{key}\}/, value.to_s)
        }
        ret
      else
        ret = gsub(/%\{/, '%%{')
        begin
    ret._old_format_m(args)
        rescue ArgumentError
    $stderr.puts "  The string:#{ret}"
    $stderr.puts "  args:#{args.inspect}"
        end
      end
    end
  end
end
