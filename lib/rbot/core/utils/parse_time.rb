#-- vim:sw=2:et
#++
#
# :title: rbot time parsing utilities
#
# Author:: Giuseppe "Oblomov" Bilotta <giuseppe.bilotta@gmail.com>
#
# These routines read a string and return the number of seconds they
# represent.

module ::Irc
  module Utils
    module ParseTime
      FLOAT_RX = /((?:\d*\.)?\d+)/

      ONE_TO_NINE = {
        :one => 1,
        :two => 2,
        :three => 3,
        :four => 4,
        :five => 5,
        :six => 6,
        :seven => 7,
        :eight => 8,
        :nine => 9,
      }

      ONE_TO_NINE_RX = Regexp.new ONE_TO_NINE.keys.join('|')

      TEENS_ETC = {
        :an => 1,
        :a => 1,
        :ten => 10,
        :eleven => 11,
        :twelve => 12,
        :thirteen => 13,
        :fourteen => 14,
        :fifteen => 15,
        :sixteen => 16,
        :seventeen => 17,
        :eighteen => 18,
        :nineteen => 19,
      }

      TEENS_ETC_RX = Regexp.new TEENS_ETC.keys.join('|')

      ENTIES = {
        :twenty => 20,
        :thirty => 30,
        :forty => 40,
        :fifty => 50,
        :sixty => 60,
      }

      ENTIES_RX = Regexp.new ENTIES.keys.join('|')

      LITNUM_RX = /(#{ONE_TO_NINE_RX})|(#{TEENS_ETC_RX})|(#{ENTIES_RX})\s*(#{ONE_TO_NINE_RX})?/

        FRACTIONS = {
        :"half" => 0.5,
        :"half a" => 0.5,
        :"half an" => 0.5,
        :"a half" => 0.5,
        :"a quarter" => 0.25,
        :"a quarter of" => 0.25,
        :"a quarter of a" => 0.25,
        :"a quarter of an" => 0.25,
        :"three quarter" => 0.75,
        :"three quarters" => 0.75,
        :"three quarter of" => 0.75,
        :"three quarters of" => 0.75,
        :"three quarter of a" => 0.75,
        :"three quarters of a" => 0.75,
        :"three quarter of an" => 0.75,
        :"three quarters of an" => 0.75,
      }

      FRACTION_RX = Regexp.new FRACTIONS.keys.join('|')

      UNITSPEC_RX = /(years?|months?|s(?:ec(?:ond)?s?)?|m(?:in(?:ute)?s?)?|h(?:(?:ou)?rs?)?|d(?:ays?)?|weeks?)/

      # str must much UNITSPEC_RX
      def ParseTime.time_unit(str)
        case str[0,1].intern
        when :s
          1
        when :m
          if str[1,1] == 'o'
            # months
            3600*24*30
          else
            #minutes
            60
          end
        when :h
          3600
        when :d
          3600*24
        when :w
          3600*24*7
        when :y
          3600*24*365
        end
      end

      # example: half an hour, two and a half weeks, 5 seconds, an hour and 5 minutes
      def ParseTime.parse_period(str)
        clean = str.gsub(/\s+/, ' ').strip

        sofar = 0
        until clean.empty?
          if clean.sub!(/^(#{FRACTION_RX})\s+#{UNITSPEC_RX}/, '')
            # fraction followed by unit
            num = FRACTIONS[$1.intern]
            unit = ParseTime.time_unit($2)
          elsif clean.sub!(/^#{FLOAT_RX}\s*(?:\s+and\s+(#{FRACTION_RX})\s+)?#{UNITSPEC_RX}/, '')
            # float plus optional fraction followed by unit
            num = $1.to_f
            frac = $2
            unit = ParseTime.time_unit($3)
            clean.strip!
            if frac.nil? and clean.sub!(/^and\s+(#{FRACTION_RX})/, '')
              frac = $1
            end
            if frac
              num += FRACTIONS[frac.intern]
            end
          elsif clean.sub!(/^(?:#{LITNUM_RX})\s+(?:and\s+(#{FRACTION_RX})\s+)?#{UNITSPEC_RX}/, '')
            if $1
              num = ONE_TO_NINE[$1.intern]
            elsif $2
              num = TEENS_ETC[$2.intern]
            elsif $3
              num = ENTIES[$3.intern]
              if $4
                num += ONE_TO_NINE[$4.intern]
              end
            end
            frac = $5
            unit = ParseTime.time_unit($6)
            clean.strip!
            if frac.nil? and clean.sub!(/^and\s+(#{FRACTION_RX})/, '')
              frac = $1
            end
            if frac
              num += FRACTIONS[frac.intern]
            end
          else
            raise "invalid time string: #{clean} (parsed #{sofar} so far)"
          end
          sofar += num * unit
          clean.sub!(/^and\s+/, '')
        end
        return sofar
      end

      # TODO 'at hh:mm:ss', 'next week, 'tomorrow', 'saturday' etc
    end

    def Utils.parse_time_offset(str)
      case str
      when /^(\d+):(\d+)(?:\:(\d+))?$/ # TODO refactor
        hour = $1.to_i
        min = $2.to_i
        sec = $3.to_i
        now = Time.now
        later = Time.mktime(now.year, now.month, now.day, hour, min, sec)

        # if the given hour is earlier than current hour, given timestr
        # must have been meant to be in the future
        if hour < now.hour || hour <= now.hour && min < now.min
          later += 60*60*24
        end

        return later - now
      when /^(\d+):(\d+)(am|pm)$/ # TODO refactor
        hour = $1.to_i
        min = $2.to_i
        ampm = $3
        if ampm == "pm"
          hour += 12
        end
        now = Time.now
        later = Time.mktime(now.year, now.month, now.day, hour, min, now.sec)
        return later - now
      else
        ParseTime.parse_period(str)
      end
    end

  end
end

