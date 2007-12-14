module Irc
  class NetmaskDb
    # helper backend class: generic nested radix tree
    class Tree
      attr_reader :pre, :chi

      def initialize(pre = '', chi = Hash.new)
        @pre = pre
        @chi = chi
      end

      def add(val, *prefs)
        str = prefs.shift or raise 'empty prefs'
        @pre = str.dup if @chi.empty?

        n = 0
        @pre.size.times do
          break if @pre[n] != str[n]
          n += 1
        end

        rest = str.slice(n .. -1)

        if n != @pre.size
          prest = @pre.slice!(n .. -1)
          pc = prest.slice! 0
          @chi = {pc => Tree.new(prest, @chi)}
        end

        c = rest.slice!(0)

        if c
          (@chi[c] ||= Tree.new).add(val, rest, *prefs)
        else
          if prefs.empty?
            (@chi[''] ||= Array.new).push val
          else
            (@chi[''] ||= Tree.new).add(val, *prefs)
          end
        end
      end

      def empty?
        @chi.empty?
      end

      def remove(*prefs, &block)
        str = prefs.shift or raise 'empty prefs?'
        return nil unless @pre.empty? or str.index(@pre) == 0
        c = str.slice(@pre.size) || ''
        return nil unless @chi.include? c
        if c == ''
          if prefs.empty?
            @chi[c].reject!(&block)
          else
            @chi[c].remove(*prefs, &block)
          end
        else
          @chi[c].remove(str.slice((@pre.size + 1) .. -1), *prefs, &block)
        end
        @chi.delete(c) if @chi[c].empty?

        if @chi.size == 1
          k = @chi.keys.shift
          return nil if k == ''
          @pre << k << @chi[k].pre
          @chi = @chi[k].chi
        end
      end

      def find(*prefs)
        str = prefs.shift or raise 'empty prefs?'
        self.find_helper(str, *prefs) + self.find_helper(str.reverse, *prefs)
      end

      protected
      def find_helper(*prefs)
        str = prefs.shift or raise 'empty prefs?'
        return [] unless @pre.empty? or str.index(@pre) == 0
        # puts "#{self.inspect}: #{str} == #{@pre} pfx matched"
        if !@chi.include? ''
          matches = []
        elsif Array === @chi['']
          matches = @chi['']
        else
          matches = @chi[''].find(*prefs)
        end

        c = str.slice(@pre.size)

        more = []
        if c and @chi.include?(c)
          more = @chi[c].find_helper(str.slice((@pre.size + 1) .. -1), *prefs)
        end
        return more + matches
      end
    end

    # api wrapper for netmasks

    def initialize
      @tree = Tree.new
    end

    def cook_component(str)
      s = (str && !str.empty?) ? str : '*'
      l = s.index(/[\?\*]/)
      if l
        l2 = s.size - s.rindex(/[\?\*]/) - 1
        if l2 > l
          s = s.reverse
          l = l2
        end

        return (l > 0) ? s.slice(0 .. (l - 1)) : ''
      else
        return s
      end
    end

    def mask2keys(m)
      md = m.downcased
      [md.host, md.user, md.nick].map { |c| cook_component(c) }
    end

    def add(user, *masks)
      masks.each do |m|
        debug "adding user #{user} with mask #{m.fullform}"
        @tree.add([user, m], *mask2keys(m))
      end
    end

    def remove(user, mask)
      debug "trying to remove user #{user} with mask #{mask}"
      @tree.remove(*mask2keys(mask)) do |val|
        val[0] == user and val[1].fullform == mask.fullform
      end
    end

    def metric(iu, bu, mask)
      ret = nil
      if iu.matches? mask
        ret = iu.fullform.length - mask.fullform.length
        ret += 10 if bu.transient?
      end
      return ret
    end

    def find(iu)
      debug "find(#{iu.fullform})"
      iud = iu.downcased
      matches = @tree.find(iud.host, iud.user, iud.nick).uniq.map do |val|
        m = metric(iu, *val)
        m ? [val[0], m] : nil
      end.compact.sort { |a, b| a[1] <=> a[1] }
      debug "matches: " + (matches.map do |m|
        "#{m[0].username}: [#{m[1]}]"
      end.join(', '))
      return matches.empty? ? nil : matches[0][0]
    end
  end
end
