module Irc

  # +MessageMapper+ is a class designed to reduce the amount of regexps and
  # string parsing plugins and bot modules need to do, in order to process
  # and respond to messages.
  #
  # You add templates to the MessageMapper which are examined by the handle
  # method when handling a message. The templates tell the mapper which
  # method in its parent class (your class) to invoke for that message. The
  # string is split, optionally defaulted and validated before being passed
  # to the matched method.
  #
  # A template such as "foo :option :otheroption" will match the string "foo
  # bar baz" and, by default, result in method +foo+ being called, if
  # present, in the parent class. It will receive two parameters, the
  # Message (derived from BasicUserMessage) and a Hash containing
  #   {:option => "bar", :otheroption => "baz"}
  # See the #map method for more details.
  class MessageMapper
    # used to set the method name used as a fallback for unmatched messages.
    # The default fallback is a method called "usage".
    attr_writer :fallback

    # parent::   parent class which will receive mapped messages
    #
    # create a new MessageMapper with parent class +parent+. This class will
    # receive messages from the mapper via the handle() method.
    def initialize(parent)
      @parent = parent
      @templates = Array.new
      @fallback = 'usage'
    end

    # args:: hash format containing arguments for this template
    #
    # map a template string to an action. example:
    #   map 'myplugin :parameter1 :parameter2'
    # (other examples follow). By default, maps a matched string to an
    # action with the name of the first word in the template. The action is
    # a method which takes a message and a parameter hash for arguments.
    #
    # The :action => 'method_name' option can be used to override this
    # default behaviour. Example:
    #   map 'myplugin :parameter1 :parameter2', :action => 'mymethod'
    #
    # By default whether a handler is fired depends on an auth check. The
    # first component of the string is used for the auth check, unless
    # overridden via the :auth => 'auth_name' option.
    #
    # Static parameters (not prefixed with ':' or '*') must match the
    # respective component of the message exactly. Example:
    #   map 'myplugin :foo is :bar'
    # will only match messages of the form "myplugin something is
    # somethingelse"
    #
    # Dynamic parameters can be specified by a colon ':' to match a single
    # component (whitespace seperated), or a * to suck up all following
    # parameters into an array. Example:
    #   map 'myplugin :parameter1 *rest'
    #
    # You can provide defaults for dynamic components using the :defaults
    # parameter. If a component has a default, then it is optional. e.g:
    #   map 'myplugin :foo :bar', :defaults => {:bar => 'qux'}
    # would match 'myplugin param param2' and also 'myplugin param'. In the
    # latter case, :bar would be provided from the default.
    #
    # Components can be validated before being allowed to match, for
    # example if you need a component to be a number:
    #   map 'myplugin :param', :requirements => {:param => /^\d+$/}
    # will only match strings of the form 'myplugin 1234' or some other
    # number.
    #
    # Templates can be set not to match public or private messages using the
    # :public or :private boolean options.
    #
    # Further examples:
    #
    #   # match 'karmastats' and call my stats() method
    #   map 'karmastats', :action => 'stats'
    #   # match 'karma' with an optional 'key' and call my karma() method
    #   map 'karma :key', :defaults => {:key => false}
    #   # match 'karma for something' and call my karma() method
    #   map 'karma for :key'
    #
    #   # two matches, one for public messages in a channel, one for
    #   # private messages which therefore require a channel argument
    #   map 'urls search :channel :limit :string', :action => 'search',
    #             :defaults => {:limit => 4},
    #             :requirements => {:limit => /^\d+$/},
    #             :public => false
    #   plugin.map 'urls search :limit :string', :action => 'search',
    #             :defaults => {:limit => 4},
    #             :requirements => {:limit => /^\d+$/},
    #             :private => false
    #
    def map(botmodule, *args)
      @templates << Template.new(botmodule, *args)
    end

    def each
      @templates.each {|tmpl| yield tmpl}
    end

    def last
      @templates.last
    end

    # m::  derived from BasicUserMessage
    #
    # examine the message +m+, comparing it with each map()'d template to
    # find and process a match. Templates are examined in the order they
    # were map()'d - first match wins.
    #
    # returns +true+ if a match is found including fallbacks, +false+
    # otherwise.
    def handle(m)
      return false if @templates.empty?
      failures = []
      @templates.each do |tmpl|
        options, failure = tmpl.recognize(m)
        if options.nil?
          failures << [tmpl, failure]
        else
          action = tmpl.options[:action] ? tmpl.options[:action] : tmpl.items[0]
          unless @parent.respond_to?(action)
            failures << [tmpl, "class does not respond to action #{action}"]
            next
          end
          auth = tmpl.options[:full_auth_path]
          debug "checking auth for #{auth}"
          if m.bot.auth.allow?(auth, m.source, m.replyto)
            debug "template match found and auth'd: #{action.inspect} #{options.inspect}"
            @parent.send(action, m, options)
            return true
          end
          debug "auth failed for #{auth}"
          # if it's just an auth failure but otherwise the match is good,
          # don't try any more handlers
          return false
        end
      end
      failures.each {|f, r|
        debug "#{f.inspect} => #{r}"
      }
      debug "no handler found, trying fallback"
      if @fallback != nil && @parent.respond_to?(@fallback)
        if m.bot.auth.allow?(@fallback, m.source, m.replyto)
          @parent.send(@fallback, m, {})
          return true
        end
      end
      return false
    end

  end

  class Template
    attr_reader :defaults # The defaults hash
    attr_reader :options  # The options hash
    attr_reader :items
    attr_reader :regexp

    def initialize(botmodule, template, hash={})
      raise ArgumentError, "Third argument must be a hash!" unless hash.kind_of?(Hash)
      @defaults = hash[:defaults].kind_of?(Hash) ? hash.delete(:defaults) : {}
      @requirements = hash[:requirements].kind_of?(Hash) ? hash.delete(:requirements) : {}
      # The old way matching was done, this prepared the match items.
      # Now we use for some preliminary syntax checking and to get the words used in the auth_path
      self.items = template
      self.regexp = template
      debug "Command #{template.inspect} in #{botmodule} will match using #{@regexp}"
      if hash.has_key?(:auth)
        warning "Command #{template.inspect} in #{botmodule} uses old :auth syntax, please upgrade"
      end
      if hash.has_key?(:full_auth_path)
        warning "Command #{template.inspect} in #{botmodule} sets :full_auth_path, please don't do this"
      else
        case botmodule
        when String
          pre = botmodule
        when Plugins::BotModule
          pre = botmodule.name
        else
          raise ArgumentError, "Can't find auth base in #{botmodule.inspect}"
        end
        words = items.reject{ |x|
          x == pre || x.kind_of?(Symbol) || x =~ /\[|\]/
        }
        if words.empty?
          post = nil
        else
          post = words.first
        end
        if hash.has_key?(:auth_path)
          extra = hash[:auth_path]
          if extra.sub!(/^:/, "")
            pre += "::" + post
            post = nil
          end
          if extra.sub!(/:$/, "")
            if words.length > 1
              post = [post,words[1]].compact.join("::")
            end
          end
          pre = nil if extra.sub!(/^!/, "")
          post = nil if extra.sub!(/!$/, "")
        else
          extra = nil
        end
        hash[:full_auth_path] = [pre,extra,post].compact.join("::")
        debug "Command #{template} in #{botmodule} will use authPath #{hash[:full_auth_path]}"
        # TODO check if the full_auth_path is sane
      end

      @options = hash

      # @dyn_items is an array of arrays whose first entry is the Symbol
      # (without the *, if any) of a dynamic item, and whose second entry is
      # false if the Symbol refers to a single-word item, or true if it's
      # multiword. @dyn_items.first will be the template.
      @dyn_items = @items.collect { |it|
        if it.kind_of?(Symbol)
          i = it.to_s
          if i.sub!(/^\*/,"")
            [i.intern, true]
          else
            [i.intern, false]
          end
        else
          nil
        end
      }
      @dyn_items.unshift(template).compact!
      debug "Items: #{@items.inspect}; dyn items: #{@dyn_items.inspect}"

      # debug "Create template #{self.inspect}"
    end

    def items=(str)
      raise ArgumentError, "template #{str.inspect} should be a String" unless str.kind_of?(String)

      # split and convert ':xyz' to symbols
      items = str.strip.split(/\]?\s+\[?/).collect { |c|
        # there might be extra (non-alphanumeric) stuff (e.g. punctuation) after the symbol name
        if /^(:|\*)(\w+)(.*)/ =~ c
          sym = ($1 == ':' ) ? $2.intern : "*#{$2}".intern
          if $3.empty?
            sym
          else
            [sym, $3]
          end
        else
          c
        end
      }.flatten
      @items = items

      raise ArgumentError, "Illegal template -- first component cannot be dynamic: #{str.inspect}" if @items.first.kind_of? Symbol

      raise ArgumentError, "Illegal template -- first component cannot be optional: #{str.inspect}" if @items.first =~ /\[|\]/

      # Verify uniqueness of each component.
      @items.inject({}) do |seen, item|
        if item.kind_of? Symbol
          # We must remove the initial * when present,
          # because the parameters hash will intern both :item and *item as :item
          it = item.to_s.sub(/^\*/,"").intern
          raise ArgumentError, "Illegal template -- duplicate item #{it} in #{str.inspect}" if seen.key? it
          seen[it] = true
        end
        seen
      end
    end

    def regexp=(str)
      # debug "Original string: #{str.inspect}"
      rx = Regexp.escape(str)
      # debug "Escaped: #{rx.inspect}"
      rx.gsub!(/((?:\\ )*)(:|\\\*)(\w+)/) { |m|
        not_needed = @defaults.has_key?($3.intern)
        s = "#{not_needed ? "(?:" : ""}#{$1}(#{$2 == ":" ? "\\S+" : ".*"})#{ not_needed ? ")?" : ""}"
      }
      # debug "Replaced dyns: #{rx.inspect}"
      rx.gsub!(/((?:\\ )*)\\\[/, "(?:\\1")
      rx.gsub!(/\\\]/, ")?")
      # debug "Delimited optionals: #{rx.inspect}"
      rx.gsub!(/(?:\\ )+/, "\\s+")
      # debug "Corrected spaces: #{rx.inspect}"
      @regexp = Regexp.new(rx)
    end

    # Recognize the provided string components, returning a hash of
    # recognized values, or [nil, reason] if the string isn't recognized.
    def recognize(m)

      debug "Testing #{m.message.inspect} against #{self.inspect}"

      # Early out
      return nil, "template #{@dyn_items.first.inspect} is not configured for private messages" if @options.has_key?(:private) && !@options[:private] && m.private?
      return nil, "template #{@dyn_items.first.inspect} is not configured for public messages" if @options.has_key?(:public) && !@options[:public] && !m.private?

      options = {}

      matching = @regexp.match(m.message)
      return nil, "#{m.message.inspect} doesn't match #{@dyn_items.first.inspect} (#{@regexp})" unless matching
      return nil, "#{m.message.inspect} only matches #{@dyn_items.first.inspect} (#{@regexp}) partially" unless matching[0] == m.message

      debug_match = matching[1..-1].collect{ |d| d.inspect}.join(', ')
      debug "#{m.message.inspect} matched #{@regexp} with #{debug_match}"
      debug "Associating #{debug_match} with dyn items #{@dyn_items[1..-1].join(', ')}"

      (@dyn_items.length - 1).downto 1 do |i|
        it = @dyn_items[i]
        item = it[0]
        debug "dyn item #{item} (multi-word: #{it[1].inspect})"
        if it[1]
          if matching[i].nil?
            default = @defaults[item]
            case default
            when Array
              value = default.clone
            when String
              value = default.strip.split
            when nil, false, []
              value = []
            else
              value = []
              warning "Unmanageable default #{default} detected for :*#{item.to_s}, using []"
            end
            case default
            when String
              value.instance_variable_set(:@string_value, default)
            else
              value.instance_variable_set(:@string_value, value.join(' '))
            end
          else
            value = matching[i].split
            value.instance_variable_set(:@string_value, matching[i])
          end
          def value.to_s
            @string_value
          end
          options[item] = value
          debug "set #{item} to #{value.inspect}"
        else
          if matching[i]
            value = matching[i]
            unless passes_requirements?(item, value)
              if @defaults.has_key?(item)
                value == @defaults[item]
              else
                return nil, requirements_for(item)
              end
            end
          else
            value = @defaults[item]
            warning "No default value for option #{item.inspect} specified" unless @defaults.has_key?(item)
          end
          options[item] = value
          debug "set #{item} to #{options[item].inspect}"
        end
      end

      options.delete_if {|k, v| v.nil?} # Remove nil values.
      return options, nil
    end

    def inspect
      when_str = @requirements.empty? ? "" : " when #{@requirements.inspect}"
      default_str = @defaults.empty? ? "" : " || #{@defaults.inspect}"
      "<#{self.class.to_s} #{@items.map { |c| c.inspect }.join(' ').inspect}#{default_str}#{when_str}>"
    end

    # Verify that the given value passes this template's requirements
    def passes_requirements?(name, value)
      return @defaults.key?(name) && @defaults[name].nil? if value.nil? # Make sure it's there if it should be

      case @requirements[name]
        when nil then true
        when Regexp then
          value = value.to_s
          match = @requirements[name].match(value)
          match && match[0].length == value.length
        else
          @requirements[name] == value.to_s
      end
    end

    def requirements_for(name)
      name = name.to_s.sub(/^\*/,"").intern if (/^\*/ =~ name.inspect)
      presence = (@defaults.key?(name) && @defaults[name].nil?)
      requirement = case @requirements[name]
        when nil then nil
        when Regexp then "match #{@requirements[name].inspect}"
        else "be equal to #{@requirements[name].inspect}"
      end
      if presence && requirement then "#{name} must be present and #{requirement}"
      elsif presence || requirement then "#{name} must #{requirement || 'be present'}"
      else "#{name} has no requirements"
      end
    end
  end
end
