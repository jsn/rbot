#-- vim:sw=2:et
#++
#
# :title: Stream filters
#
# Author:: Giuseppe "Oblomov" Bilotta <giuseppe.bilotta@gmail.com>
# Copyright:: (C) 2008 Giuseppe Bilotta
# License:: GPL v2
#
# This file collects methods to handle 'stream filters', a generic mechanism
# to transform text+attributes into other text+attributes

module ::Irc
  class Bot

    # The DataStream class. A DataStream is just a Hash. The :text key has
    # a special meaning because it's the value that will be used when
    # converting to String
    class DataStream < Hash

      # call-seq: new(text, hash)
      #
      # Create a new DataStream with text _text_ and attributes held by _hash_.
      # Either parameter can be missing; if _text_ is missing, the text can be
      # be defined in the _hash_ with a :text key.
      #
      def initialize(*args)
        self.replace(args.pop) if Hash === args.last
        self[:text] = args.first if args.length > 0
      end

      # Returns the :text key
      def to_s
        return self[:text]
      end
    end

    # The DataFilter class. A DataFilter is a wrapper around a block
    # that can be run on a DataStream to process it. The block is supposed to
    # return another DataStream object
    class DataFilter
      def initialize(&block)
        raise "No block provided" unless block_given?
        @block = block
      end

      def call(stream)
        @block.call(stream)
      end
      alias :run :call
      alias :filter :call
    end

    # call-seq:
    #   filter(filter1, filter2, ..., filterN, stream) -> stream
    #   filter(filter1, filter2, ..., filterN, text, hash) -> stream
    #   filter(filter1, filter2, ..., filterN, hash) -> stream
    #
    # This method processes the DataStream _stream_ with the filters <i>filter1</i>,
    # <i>filter2</i>, ..., _filterN_, in sequence (the output of each filter is used
    # as input for the next one.
    # _stream_ can be provided either as a DataStream or as a String and a Hash
    # (see DataStream.new).
    #
    def filter(*args)
      @filters ||= {}
      case args.last
      when DataStream
        # the stream is an actual DataStream
        ds = args.pop
      when String
        # the stream is just plain text
        ds = DataStream.new(args.pop)
      when Hash
        # the stream is a Hash, check if the previous element is a String
        if String === args[-2]
          ds = DataStream.new(*args.slice!(-2, 2))
        else
          ds = DataStream.new(args.pop)
        end
      else
        raise "Unknown DataStream class #{args.last.class}"
      end
      names = args.dup
      return ds if names.empty?
      # check if filters exist
      missing = names - @filters.keys
      raise "Missing filters: #{missing.join(', ')}" unless missing.empty?
      fs = @filters.values_at(*names)
      fs.inject(ds) { |mid, f| mid = f.call(mid) }
    end

    # This method is used to register a new filter
    def register_filter(name, group=nil, &block)
      raise "No block provided" unless block_given?
      @filters ||= {}
      tlkey = ( group ? "#{group}.#{name}" : name.to_s ).intern
      key = name.to_sym
      if @filters.key?(tlkey)
        debug "Overwriting filter #{tlkey}"
      end
      @filters[tlkey] = DataFilter.new &block
      if group
        gkey = group.to_sym
        @filter_group ||= {}
        @filter_group[gkey] ||= {}
        if @filter_group[gkey].key?(key)
          debug "Overwriting filter #{key} in group #{gkey}"
        end
        @filter_group[gkey][key] = @filters[tlkey]
      end
    end

    # This method clears the filter list and installs the identity filter
    def clear_filters
      @filters ||= {}
      @filters.clear

      @filter_group ||= {}
      @filter_group.clear

      register_filter(:identity) { |stream| stream }
    end
  end
end


