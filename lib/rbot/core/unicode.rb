#-- vim:sw=4:et
#++
#
# :title: Unicode plugin
#
# Author:: jsn (Dmitry Kim) <dmitry dot kim at gmail dot org>
#
# This plugin adds unicode-awareness to rbot. When it's loaded, all the
# character strings inside of rbot are assumed to be in proper utf-8
# encoding. The plugin takes care of translation to/from utf-8 on server IO,
# if necessary (translation charsets are configurable).

# TODO autoconfigure using server-provided allowed charset when these are
# available, see also comment in irc.rb

require 'iconv'

class UnicodePlugin < CoreBotModule
    Config.register Config::BooleanValue.new(
    'encoding.enable', :default => true,
    :desc => "Support for non-ascii charsets",
    :on_change => Proc.new { |bot, v| reconfigure_filter(bot) })

    Config.register Config::ArrayValue.new(
    'encoding.charsets', :default => ['utf-8', 'cp1252', 'iso-8859-15'],
    :desc => "Ordered list of iconv(3) charsets the bot should try",
    :validate_item => Proc.new { |x| !!(Iconv.new('utf-8', x) rescue nil) },
    :on_change => Proc.new { |bot, v| reconfigure_filter(bot) })

    class UnicodeFilter
        def initialize(oenc, *iencs)
            o = oenc.dup
            o += '//ignore' if !o.include?('/')
            i = iencs[0].dup
            # i += '//ignore' if !i.include?('/')
            @iencs = iencs.dup
            @iconvs = @iencs.map { |_| Iconv.new('utf-8', _) }
            debug "*** o = #{o}, i = #{i}, iencs = #{iencs.inspect}"
            @default_in = Iconv.new('utf-8//ignore', i)
            @default_out = Iconv.new(o, 'utf-8//ignore')
        end

        def in(data)
            rv = nil
            @iconvs.each_with_index { |ic, idx|
                begin
                    debug "trying #{@iencs[idx]}"
                    rv = ic.iconv(data)
                    break
                rescue
                end
            }

            rv = @default_in.iconv(data) if !rv
            debug ">> #{rv.inspect}"
            return rv
        end

        def out(data)
            rv = @default_out.iconv(data) rescue data # XXX: yeah, i know :/
            debug "<< #{rv}"
            rv
        end
    end


    def initialize(*a)
        super
        @@old_kcode = $KCODE
        self.class.reconfigure_filter(@bot)
    end

    def cleanup
        debug "cleaning up encodings"
        @bot.socket.filter = nil
        $KCODE = @@old_kcode
        super
    end

    def UnicodePlugin.reconfigure_filter(bot)
        debug "configuring encodings"
        enable = bot.config['encoding.enable']
        if not enable
            bot.socket.filter = nil
            $KCODE = @@old_kcode
            return
        end
        charsets = bot.config['encoding.charsets']
        charsets = ['utf-8'] if charsets.empty?
        bot.socket.filter = UnicodeFilter.new(charsets[0], *charsets)
        $KCODE = 'u'
    end
end

UnicodePlugin.new
