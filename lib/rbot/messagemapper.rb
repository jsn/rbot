module Irc
  class MessageMapper
    attr_writer :fallback

    def initialize(parent)
      @parent = parent
      @routes = Array.new
      @fallback = 'usage'
    end
    
    def map(*args)
      @routes << Template.new(*args)
    end
    
    def each
      @routes.each {|route| yield route}
    end
    def last
      @routes.last
    end
    
    def handle(m)
      return false if @routes.empty?
      failures = []
      @routes.each do |route|
        options, failure = route.recognize(m)
        if options.nil?
          failures << [route, failure]
        else
          action = route.options[:action] ? route.options[:action] : route.items[0]
          next unless @parent.respond_to?(action)
          auth = route.options[:auth] ? route.options[:auth] : action
          if m.bot.auth.allow?(auth, m.source, m.replyto)
            debug "route found and auth'd: #{action.inspect} #{options.inspect}"
            @parent.send(action, m, options)
            return true
          end
          # if it's just an auth failure but otherwise the match is good,
          # don't try any more handlers
          break
        end
      end
      debug failures.inspect
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
          raise ArgumentError, "Illegal template -- duplicate item #{item}\n   #{str.inspect}" if seen.key? item
          seen[item] = true
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

      return nil, "route is not configured for private messages" if @options.has_key?(:private) && !@options[:private] && m.private?
      return nil, "route is not configured for public messages" if @options.has_key?(:public) && !@options[:public] && !m.private?
      
      options.delete_if {|k, v| v.nil?} # Remove nil values.
      return options, nil
    end

    def inspect
      when_str = @requirements.empty? ? "" : " when #{@requirements.inspect}"
      default_str = @defaults.empty? ? "" : " || #{@defaults.inspect}"
      "<#{self.class.to_s} #{@items.collect{|c| c.kind_of?(String) ? c : c.inspect}.join(' ').inspect}#{default_str}#{when_str}>"
    end

    # Verify that the given value passes this route's requirements
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
