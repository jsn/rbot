# load gettext module and provide fallback in case of failure

require 'stringio'

# try to load gettext, or provide fake getttext functions
begin
  require 'gettext'
  include GetText
  bindtextdomain 'rbot'

  module GetText
    # patch for ruby-gettext 1.9.0 to cope with anonymous modules used by rbot
    # FIXME remove the patch when ruby-gettext is fixed, or rbot switches to named modules
  # fix for module names that are not constant names
    if !instance_methods.include?('orig_bound_targets')
      alias :orig_bound_targets :bound_targets
    end
    def bound_targets(*a)  # :nodoc:
      orig_bound_targets(*a) rescue orig_bound_targets(Object)
    end
  end

  begin
    gettext_info = StringIO.new
    current_textdomain_info(:out=>gettext_info) # fails sometimes
    debug 'using ruby-gettext'
    gettext_info.string.each_line {|l| debug l}
  rescue Exception
  end

rescue LoadError
  warn 'ruby-gettext package not available; translations are disabled'

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

  def s_(*args)
    args[0]
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
