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
    def map(*args)
      @templates << Template.new(*args)
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
          auth = tmpl.options[:auth] ? tmpl.options[:auth] : tmpl.items[0]
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
    def initialize(template, hash={})
      raise ArgumentError, "Second argument must be a hash!" unless hash.kind_of?(Hash)
      @defaults = hash[:defaults].kind_of?(Hash) ? hash.delete(:defaults) : {}
      @requirements = hash[:requirements].kind_of?(Hash) ? hash.delete(:requirements) : {}
      self.items = template
      @options = hash
    end
    def items=(str)
      items = str.split(/\s+/).collect {|c| (/^(:|\*)(\w+)$/ =~ c) ? (($1 == ':' ) ? $2.intern : "*#{$2}".intern) : c} if str.kind_of?(String) # split and convert ':xyz' to symbols
      items.shift if items.first == ""
      items.pop if items.last == ""
      @items = items

      if @items.first.kind_of? Symbol
        raise ArgumentError, "Illegal template -- first component cannot be dynamic\n   #{str.inspect}"
      end

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

    # Recognize the provided string components, returning a hash of
    # recognized values, or [nil, reason] if the string isn't recognized.
    def recognize(m)
      components = m.message.split(/\s+/)
      options = {}

      @items.each do |item|
        if /^\*/ =~ item.to_s
          if components.empty?
            value = @defaults.has_key?(item) ? @defaults[item].clone : []
          else
            value = components.clone
          end
          components = []
          def value.to_s() self.join(' ') end
          options[item.to_s.sub(/^\*/,"").intern] = value
        elsif item.kind_of? Symbol
          value = components.shift || @defaults[item]
          if passes_requirements?(item, value)
            options[item] = value
          else
            if @defaults.has_key?(item)
              options[item] = @defaults[item]
              # push the test-failed component back on the stack
              components.unshift value
            else
              return nil, requirements_for(item)
            end
          end
        else
          return nil, "No value available for component #{item.inspect}" if components.empty?
          component = components.shift
          return nil, "Value for component #{item.inspect} doesn't match #{component}" if component != item
        end
      end

      return nil, "Unused components were left: #{components.join '/'}" unless components.empty?

      return nil, "template is not configured for private messages" if @options.has_key?(:private) && !@options[:private] && m.private?
      return nil, "template is not configured for public messages" if @options.has_key?(:public) && !@options[:public] && !m.private?

      options.delete_if {|k, v| v.nil?} # Remove nil values.
      return options, nil
    end

    def inspect
      when_str = @requirements.empty? ? "" : " when #{@requirements.inspect}"
      default_str = @defaults.empty? ? "" : " || #{@defaults.inspect}"
      "<#{self.class.to_s} #{@items.collect{|c| c.kind_of?(String) ? c : c.inspect}.join(' ').inspect}#{default_str}#{when_str}>"
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
