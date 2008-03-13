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

    # This method processes the DataStream _stream_ with the filters _name_.
    # _name_ can be either a single Symbol (filter name), or an Array of
    # Symbols, in which case the output of each filter will be used as input
    # for the next
    #
    def filter(name, stream={})
      @filters ||= {}
      names = (Symbol === name ? [name] : name.dup)
      ds = (DataStream === stream ? stream : DataStream.new(stream))
      return ds if names.empty?
      # check if filters exist
      missing = names - @filters.keys
      raise "Missing filters: #{missing.join(', ')}" unless missing.empty?
      fs = @filters.values_at(*names)
      fs.inject(ds) { |mid, f| mid = f.call(mid) }
    end

    # This method is used to register a new filter
    def register_filter(name, &block)
      raise "No block provided" unless block_given?
      @filters ||= {}
      @filters[name.to_sym] = DataFilter.new &block
    end

    # This method clears the filter list and installs the identity filter
    def clear_filters
      @filters ||= {}
      @filters.clear
      register_filter(:identity) { |stream| stream }
    end
  end
end


