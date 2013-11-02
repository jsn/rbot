# encoding: UTF-8
#-- vim:sw=2:et
#++
#
# :title: rbot utilities provider
#
# Author:: Tom Gilbert <tom@linuxbrit.co.uk>
# Author:: Giuseppe "Oblomov" Bilotta <giuseppe.bilotta@gmail.com>
#
# TODO some of these Utils should be rewritten as extensions to the approriate
# standard Ruby classes and accordingly be moved to extends.rb

require 'tempfile'
require 'set'

# Try to load htmlentities, fall back to an HTML escape table.
begin
  require 'htmlentities'
rescue LoadError
    module ::Irc
      module Utils
        UNESCAPE_TABLE = {
    'laquo' => '«',
    'raquo' => '»',
    'quot' => '"',
    'apos' => '\'',
    'deg' => '°',
    'micro' => 'µ',
    'copy' => '©',
    'trade' => '™',
    'reg' => '®',
    'amp' => '&',
    'lt' => '<',
    'gt' => '>',
    'hellip' => '…',
    'nbsp' => ' ',
    'ndash' => '–',
    'Agrave' => 'À',
    'Aacute' => 'Á',
    'Acirc' => 'Â',
    'Atilde' => 'Ã',
    'Auml' => 'Ä',
    'Aring' => 'Å',
    'AElig' => 'Æ',
    'OElig' => 'Œ',
    'Ccedil' => 'Ç',
    'Egrave' => 'È',
    'Eacute' => 'É',
    'Ecirc' => 'Ê',
    'Euml' => 'Ë',
    'Igrave' => 'Ì',
    'Iacute' => 'Í',
    'Icirc' => 'Î',
    'Iuml' => 'Ï',
    'ETH' => 'Ð',
    'Ntilde' => 'Ñ',
    'Ograve' => 'Ò',
    'Oacute' => 'Ó',
    'Ocirc' => 'Ô',
    'Otilde' => 'Õ',
    'Ouml' => 'Ö',
    'Oslash' => 'Ø',
    'Ugrave' => 'Ù',
    'Uacute' => 'Ú',
    'Ucirc' => 'Û',
    'Uuml' => 'Ü',
    'Yacute' => 'Ý',
    'THORN' => 'Þ',
    'szlig' => 'ß',
    'agrave' => 'à',
    'aacute' => 'á',
    'acirc' => 'â',
    'atilde' => 'ã',
    'auml' => 'ä',
    'aring' => 'å',
    'aelig' => 'æ',
    'oelig' => 'œ',
    'ccedil' => 'ç',
    'egrave' => 'è',
    'eacute' => 'é',
    'ecirc' => 'ê',
    'euml' => 'ë',
    'igrave' => 'ì',
    'iacute' => 'í',
    'icirc' => 'î',
    'iuml' => 'ï',
    'eth' => 'ð',
    'ntilde' => 'ñ',
    'ograve' => 'ò',
    'oacute' => 'ó',
    'ocirc' => 'ô',
    'otilde' => 'õ',
    'ouml' => 'ö',
    'oslash' => 'ø',
    'ugrave' => 'ù',
    'uacute' => 'ú',
    'ucirc' => 'û',
    'uuml' => 'ü',
    'yacute' => 'ý',
    'thorn' => 'þ',
    'yuml' => 'ÿ'
        }
      end
    end
end

begin
  require 'hpricot'
  module ::Irc
    module Utils
      AFTER_PAR_PATH = /^(?:div|span)$/
      AFTER_PAR_EX = /^(?:td|tr|tbody|table)$/
      AFTER_PAR_CLASS = /body|message|text/i
    end
  end
rescue LoadError
    module ::Irc
      module Utils
        # Some regular expressions to manage HTML data

        # Title
        TITLE_REGEX = /<\s*?title\s*?>(.+?)<\s*?\/title\s*?>/im

        # H1, H2, etc
        HX_REGEX = /<h(\d)(?:\s+[^>]*)?>(.*?)<\/h\1>/im
        # A paragraph
        PAR_REGEX = /<p(?:\s+[^>]*)?>.*?<\/?(?:p|div|html|body|table|td|tr)(?:\s+[^>]*)?>/im

        # Some blogging and forum platforms use spans or divs with a 'body' or 'message' or 'text' in their class
        # to mark actual text
        AFTER_PAR1_REGEX = /<\w+\s+[^>]*(?:body|message|text|post)[^>]*>.*?<\/?(?:p|div|html|body|table|td|tr)(?:\s+[^>]*)?>/im

        # At worst, we can try stuff which is comprised between two <br>
        AFTER_PAR2_REGEX = /<br(?:\s+[^>]*)?\/?>.*?<\/?(?:br|p|div|html|body|table|td|tr)(?:\s+[^>]*)?\/?>/im
      end
    end
end

module ::Irc

  # Miscellaneous useful functions
  module Utils
    @@bot = nil unless defined? @@bot
    @@safe_save_dir = nil unless defined?(@@safe_save_dir)

    # The bot instance
    def Utils.bot
      @@bot
    end

    # Set up some Utils routines which depend on the associated bot.
    def Utils.bot=(b)
      debug "initializing utils"
      @@bot = b
      @@safe_save_dir = @@bot.path('safe_save')
    end


    # Seconds per minute
    SEC_PER_MIN = 60
    # Seconds per hour
    SEC_PER_HR = SEC_PER_MIN * 60
    # Seconds per day
    SEC_PER_DAY = SEC_PER_HR * 24
    # Seconds per week
    SEC_PER_WK = SEC_PER_DAY * 7
    # Seconds per (30-day) month
    SEC_PER_MNTH = SEC_PER_DAY * 30
    # Second per (non-leap) year
    SEC_PER_YR = SEC_PER_DAY * 365

    # Auxiliary method needed by Utils.secs_to_string
    def Utils.secs_to_string_case(array, var, string, plural)
      case var
      when 1
        array << "1 #{string}"
      else
        array << "#{var} #{plural}"
      end
    end

    # Turn a number of seconds into a human readable string, e.g
    # 2 days, 3 hours, 18 minutes and 10 seconds
    def Utils.secs_to_string(secs)
      ret = []
      years, secs = secs.divmod SEC_PER_YR
      secs_to_string_case(ret, years, _("year"), _("years")) if years > 0
      months, secs = secs.divmod SEC_PER_MNTH
      secs_to_string_case(ret, months, _("month"), _("months")) if months > 0
      days, secs = secs.divmod SEC_PER_DAY
      secs_to_string_case(ret, days, _("day"), _("days")) if days > 0
      hours, secs = secs.divmod SEC_PER_HR
      secs_to_string_case(ret, hours, _("hour"), _("hours")) if hours > 0
      mins, secs = secs.divmod SEC_PER_MIN
      secs_to_string_case(ret, mins, _("minute"), _("minutes")) if mins > 0
      secs = secs.to_i
      secs_to_string_case(ret, secs, _("second"), _("seconds")) if secs > 0 or ret.empty?
      case ret.length
      when 0
        raise "Empty ret array!"
      when 1
        return ret[0].to_s
      else
        return [ret[0, ret.length-1].join(", ") , ret[-1]].join(_(" and "))
      end
    end

    # Turn a number of seconds into a hours:minutes:seconds e.g.
    # 3:18:10 or 5'12" or 7s
    #
    def Utils.secs_to_short(seconds)
      secs = seconds.to_i # make sure it's an integer
      mins, secs = secs.divmod 60
      hours, mins = mins.divmod 60
      if hours > 0
        return ("%s:%s:%s" % [hours, mins, secs])
      elsif mins > 0
        return ("%s'%s\"" % [mins, secs])
      else
        return ("%ss" % [secs])
      end
    end

    # Returns human readable time.
    # Like: 5 days ago
    #       about one hour ago
    # options
    # :start_date, sets the time to measure against, defaults to now
    # :date_format, used with <tt>to_formatted_s<tt>, default to :default
    def Utils.timeago(time, options = {})
      start_date = options.delete(:start_date) || Time.new
      date_format = options.delete(:date_format) || "%x"
      delta = (start_date - time).round
      if delta.abs < 2
        _("right now")
      else
        distance = Utils.age_string(delta)
        if delta < 0
          _("%{d} from now") % {:d => distance}
        else
          _("%{d} ago") % {:d => distance}
        end
      end
    end

    # Converts age in seconds to "nn units". Inspired by previous attempts
    # but also gitweb's age_string() sub
    def Utils.age_string(secs)
      case
      when secs < 0
        Utils.age_string(-secs)
      when secs > 2*SEC_PER_YR
        _("%{m} years") % { :m => secs/SEC_PER_YR }
      when secs > 2*SEC_PER_MNTH
        _("%{m} months") % { :m => secs/SEC_PER_MNTH }
      when secs > 2*SEC_PER_WK
        _("%{m} weeks") % { :m => secs/SEC_PER_WK }
      when secs > 2*SEC_PER_DAY
        _("%{m} days") % { :m => secs/SEC_PER_DAY }
      when secs > 2*SEC_PER_HR
        _("%{m} hours") % { :m => secs/SEC_PER_HR }
      when (20*SEC_PER_MIN..40*SEC_PER_MIN).include?(secs)
        _("half an hour")
      when (50*SEC_PER_MIN..70*SEC_PER_MIN).include?(secs)
        # _("about one hour")
        _("an hour")
      when (80*SEC_PER_MIN..100*SEC_PER_MIN).include?(secs)
        _("an hour and a half")
      when secs > 2*SEC_PER_MIN
        _("%{m} minutes") % { :m => secs/SEC_PER_MIN }
      when secs > 1
        _("%{m} seconds") % { :m => secs }
      else
        _("one second")
      end
    end

    # Execute an external program, returning a String obtained by redirecting
    # the program's standards errors and output
    #
    # TODO: find a way to expose some common errors (e.g. Errno::NOENT)
    # to the caller
    def Utils.safe_exec(command, *args)
      output = IO.popen("-") { |p|
        if p
          break p.readlines.join("\n")
        else
          begin
            $stderr.reopen($stdout)
            exec(command, *args)
          rescue Exception => e
            puts "exception #{e.pretty_inspect} trying to run #{command}"
            Kernel::exit! 1
          end
          puts "exec of #{command} failed"
          Kernel::exit! 1
        end
      }
      raise "safe execution of #{command} returned #{$?}" unless $?.success?
      return output
    end

    # Try executing an external program, returning true if the run was successful
    # and false otherwise
    def Utils.try_exec(command, *args)
      IO.popen("-") { |p|
        if p.nil?
          begin
            $stderr.reopen($stdout)
            exec(command, *args)
          rescue Exception => e
            Kernel::exit! 1
          end
          Kernel::exit! 1
        else
          debug p.readlines
        end
      }
      debug $?
      return $?.success?
    end

    # Safely (atomically) save to _file_, by passing a tempfile to the block
    # and then moving the tempfile to its final location when done.
    #
    # call-seq: Utils.safe_save(file, &block)
    #
    def Utils.safe_save(file)
      raise 'No safe save directory defined!' if @@safe_save_dir.nil?
      basename = File.basename(file)
      temp = Tempfile.new(basename,@@safe_save_dir)
      temp.binmode
      yield temp if block_given?
      temp.close
      File.rename(temp.path, file)
    end


    # Decode HTML entities in the String _str_, using HTMLEntities if the
    # package was found, or UNESCAPE_TABLE otherwise.
    #

    if defined? ::HTMLEntities
      if ::HTMLEntities.respond_to? :decode_entities
        def Utils.decode_html_entities(str)
          return HTMLEntities.decode_entities(str)
        end
      else
        @@html_entities = HTMLEntities.new
        def Utils.decode_html_entities(str)
          return @@html_entities.decode str
        end
      end
    else
      def Utils.decode_html_entities(str)
        return str.gsub(/(&(.+?);)/) {
          symbol = $2
          # remove the 0-paddng from unicode integers
          case symbol
          when /^#x([0-9a-fA-F]+)$/
            symbol = $1.to_i(16).to_s
          when /^#(\d+)$/
            symbol = $1.to_i.to_s
          end

          # output the symbol's irc-translated character, or a * if it's unknown
          UNESCAPE_TABLE[symbol] || (symbol.match(/^\d+$/) ? [symbol.to_i].pack("U") : '*')
        }
      end
    end

    # Try to grab and IRCify the first HTML par (<p> tag) in the given string.
    # If possible, grab the one after the first heading
    #
    # It is possible to pass some options to determine how the stripping
    # occurs. Currently supported options are
    # strip:: Regex or String to strip at the beginning of the obtained
    #         text
    # min_spaces:: minimum number of spaces a paragraph should have
    #
    def Utils.ircify_first_html_par(xml_org, opts={})
      if defined? ::Hpricot
        Utils.ircify_first_html_par_wh(xml_org, opts)
      else
        Utils.ircify_first_html_par_woh(xml_org, opts)
      end
    end

    # HTML first par grabber using hpricot
    def Utils.ircify_first_html_par_wh(xml_org, opts={})
      doc = Hpricot(xml_org)

      # Strip styles and scripts
      (doc/"style|script").remove

      debug doc

      strip = opts[:strip]
      strip = Regexp.new(/^#{Regexp.escape(strip)}/) if strip.kind_of?(String)

      min_spaces = opts[:min_spaces] || 8
      min_spaces = 0 if min_spaces < 0

      txt = String.new

      pre_h = pars = by_span = nil

      while true
        debug "Minimum number of spaces: #{min_spaces}"

        # Initial attempt: <p> that follows <h\d>
        if pre_h.nil?
          pre_h = Hpricot::Elements[]
          found_h = false
          doc.search("*") { |e|
            next if e.bogusetag?
            case e.pathname
            when /^h\d/
              found_h = true
            when 'p'
              pre_h << e if found_h
            end
          }
          debug "Hx: found: #{pre_h.pretty_inspect}"
        end

        pre_h.each { |p|
          debug p
          txt = p.to_html.ircify_html
          txt.sub!(strip, '') if strip
          debug "(Hx attempt) #{txt.inspect} has #{txt.count(" ")} spaces"
          break unless txt.empty? or txt.count(" ") < min_spaces
        }

        return txt unless txt.empty? or txt.count(" ") < min_spaces

        # Second natural attempt: just get any <p>
        pars = doc/"p" if pars.nil?
        debug "par: found: #{pars.pretty_inspect}"
        pars.each { |p|
          debug p
          txt = p.to_html.ircify_html
          txt.sub!(strip, '') if strip
          debug "(par attempt) #{txt.inspect} has #{txt.count(" ")} spaces"
          break unless txt.empty? or txt.count(" ") < min_spaces
        }

        return txt unless txt.empty? or txt.count(" ") < min_spaces

        # Nothing yet ... let's get drastic: we look for non-par elements too,
        # but only for those that match something that we know is likely to
        # contain text

        # Some blogging and forum platforms use spans or divs with a 'body' or
        # 'message' or 'text' in their class to mark actual text. Since we want
        # the class match to be partial and case insensitive, we collect
        # the common elements that may have this class and then filter out those
        # we don't need. If no divs or spans are found, we'll accept additional
        # elements too (td, tr, tbody, table).
        if by_span.nil?
          by_span = Hpricot::Elements[]
          extra = Hpricot::Elements[]
          doc.search("*") { |el|
            next if el.bogusetag?
            case el.pathname
            when AFTER_PAR_PATH
              by_span.push el if el[:class] =~ AFTER_PAR_CLASS or el[:id] =~ AFTER_PAR_CLASS
            when AFTER_PAR_EX
              extra.push el if el[:class] =~ AFTER_PAR_CLASS or el[:id] =~ AFTER_PAR_CLASS
            end
          }
          if by_span.empty? and not extra.empty?
            by_span.concat extra
          end
          debug "other \#1: found: #{by_span.pretty_inspect}"
        end

        by_span.each { |p|
          debug p
          txt = p.to_html.ircify_html
          txt.sub!(strip, '') if strip
          debug "(other attempt \#1) #{txt.inspect} has #{txt.count(" ")} spaces"
          break unless txt.empty? or txt.count(" ") < min_spaces
        }

        return txt unless txt.empty? or txt.count(" ") < min_spaces

        # At worst, we can try stuff which is comprised between two <br>
        # TODO

        debug "Last candidate #{txt.inspect} has #{txt.count(" ")} spaces"
        return txt unless txt.count(" ") < min_spaces
        break if min_spaces == 0
        min_spaces /= 2
      end
    end

    # HTML first par grabber without hpricot
    def Utils.ircify_first_html_par_woh(xml_org, opts={})
      xml = xml_org.gsub(/<!--.*?-->/m,
                         "").gsub(/<script(?:\s+[^>]*)?>.*?<\/script>/im,
                         "").gsub(/<style(?:\s+[^>]*)?>.*?<\/style>/im,
                         "").gsub(/<select(?:\s+[^>]*)?>.*?<\/select>/im,
                         "")

      strip = opts[:strip]
      strip = Regexp.new(/^#{Regexp.escape(strip)}/) if strip.kind_of?(String)

      min_spaces = opts[:min_spaces] || 8
      min_spaces = 0 if min_spaces < 0

      txt = String.new

      while true
        debug "Minimum number of spaces: #{min_spaces}"
        header_found = xml.match(HX_REGEX)
        if header_found
          header_found = $'
          while txt.empty? or txt.count(" ") < min_spaces
            candidate = header_found[PAR_REGEX]
            break unless candidate
            txt = candidate.ircify_html
            header_found = $'
            txt.sub!(strip, '') if strip
            debug "(Hx attempt) #{txt.inspect} has #{txt.count(" ")} spaces"
          end
        end

        return txt unless txt.empty? or txt.count(" ") < min_spaces

        # If we haven't found a first par yet, try to get it from the whole
        # document
        header_found = xml
        while txt.empty? or txt.count(" ") < min_spaces
          candidate = header_found[PAR_REGEX]
          break unless candidate
          txt = candidate.ircify_html
          header_found = $'
          txt.sub!(strip, '') if strip
          debug "(par attempt) #{txt.inspect} has #{txt.count(" ")} spaces"
        end

        return txt unless txt.empty? or txt.count(" ") < min_spaces

        # Nothing yet ... let's get drastic: we look for non-par elements too,
        # but only for those that match something that we know is likely to
        # contain text

        # Attempt #1
        header_found = xml
        while txt.empty? or txt.count(" ") < min_spaces
          candidate = header_found[AFTER_PAR1_REGEX]
          break unless candidate
          txt = candidate.ircify_html
          header_found = $'
          txt.sub!(strip, '') if strip
          debug "(other attempt \#1) #{txt.inspect} has #{txt.count(" ")} spaces"
        end

        return txt unless txt.empty? or txt.count(" ") < min_spaces

        # Attempt #2
        header_found = xml
        while txt.empty? or txt.count(" ") < min_spaces
          candidate = header_found[AFTER_PAR2_REGEX]
          break unless candidate
          txt = candidate.ircify_html
          header_found = $'
          txt.sub!(strip, '') if strip
          debug "(other attempt \#2) #{txt.inspect} has #{txt.count(" ")} spaces"
        end

        debug "Last candidate #{txt.inspect} has #{txt.count(" ")} spaces"
        return txt unless txt.count(" ") < min_spaces
        break if min_spaces == 0
        min_spaces /= 2
      end
    end

    # This method extracts title, content (first par) and extra
    # information from the given document _doc_.
    #
    # _doc_ can be an URI, a Net::HTTPResponse or a String.
    #
    # If _doc_ is a String, only title and content information
    # are retrieved (if possible), using standard methods.
    #
    # If _doc_ is an URI or a Net::HTTPResponse, additional
    # information is retrieved, and special title/summary
    # extraction routines are used if possible.
    #
    def Utils.get_html_info(doc, opts={})
      case doc
      when String
        Utils.get_string_html_info(doc, opts)
      when Net::HTTPResponse
        Utils.get_resp_html_info(doc, opts)
      when URI
        ret = DataStream.new
        @@bot.httputil.get_response(doc) { |resp|
          ret.replace Utils.get_resp_html_info(resp, opts)
        }
        return ret
      else
        raise
      end
    end

    class ::UrlLinkError < RuntimeError
    end

    # This method extracts title, content (first par) and extra
    # information from the given Net::HTTPResponse _resp_.
    #
    # Currently, the only accepted options (in _opts_) are
    # uri_fragment:: the URI fragment of the original request
    # full_body::    get the whole body instead of
    #                @@bot.config['http.info_bytes'] bytes only
    #
    # Returns a DataStream with the following keys:
    # text:: the (partial) body
    # title:: the title of the document (if any)
    # content:: the first paragraph of the document (if any)
    # headers::
    #   the headers of the Net::HTTPResponse. The value is
    #   a Hash whose keys are lowercase forms of the HTTP
    #   header fields, and whose values are Arrays.
    #
    def Utils.get_resp_html_info(resp, opts={})
      case resp
      when Net::HTTPSuccess
        loc = URI.parse(resp['x-rbot-location'] || resp['location']) rescue nil
        if loc and loc.fragment and not loc.fragment.empty?
          opts[:uri_fragment] ||= loc.fragment
        end
        ret = DataStream.new(opts.dup)
        ret[:headers] = resp.to_hash
        ret[:text] = partial = opts[:full_body] ? resp.body : resp.partial_body(@@bot.config['http.info_bytes'])

        filtered = Utils.try_htmlinfo_filters(ret)

        if filtered
          return filtered
        elsif resp['content-type'] =~ /^text\/|(?:x|ht)ml/
          ret.merge!(Utils.get_string_html_info(partial, opts))
        end
        return ret
      else
        raise UrlLinkError, "getting link (#{resp.code} - #{resp.message})"
      end
    end

    # This method runs an appropriately-crafted DataStream _ds_ through the
    # filters in the :htmlinfo filter group, in order. If one of the filters
    # returns non-nil, its results are merged in _ds_ and returned. Otherwise
    # nil is returned.
    #
    # The input DataStream should have the downloaded HTML as primary key
    # (:text) and possibly a :headers key holding the resonse headers.
    #
    def Utils.try_htmlinfo_filters(ds)
      filters = @@bot.filter_names(:htmlinfo)
      return nil if filters.empty?
      cur = nil
      # TODO filter priority
      filters.each { |n|
        debug "testing htmlinfo filter #{n}"
        cur = @@bot.filter(@@bot.global_filter_name(n, :htmlinfo), ds)
        debug "returned #{cur.pretty_inspect}"
        break if cur
      }
      return ds.merge(cur) if cur
    end

    # HTML info filters often need to check if the webpage location
    # of a passed DataStream _ds_ matches a given Regexp.
    def Utils.check_location(ds, rx)
      debug ds[:headers]
      if h = ds[:headers]
        loc = [h['x-rbot-location'],h['location']].flatten.grep(rx)
      end
      loc ||= []
      debug loc
      return loc.empty? ? nil : loc
    end

    # This method extracts title and content (first par)
    # from the given HTML or XML document _text_, using
    # standard methods (String#ircify_html_title,
    # Utils.ircify_first_html_par)
    #
    # Currently, the only accepted option (in _opts_) is
    # uri_fragment:: the URI fragment of the original request
    #
    def Utils.get_string_html_info(text, opts={})
      debug "getting string html info"
      txt = text.dup
      title = txt.ircify_html_title
      debug opts
      if frag = opts[:uri_fragment] and not frag.empty?
        fragreg = /<a\s+(?:[^>]+\s+)?(?:name|id)=["']?#{frag}["']?[^>]*>/im
        debug fragreg
        debug txt
        if txt.match(fragreg)
          # grab the post-match
          txt = $'
        end
        debug txt
      end
      c_opts = opts.dup
      c_opts[:strip] ||= title
      content = Utils.ircify_first_html_par(txt, c_opts)
      content = nil if content.empty?
      return {:title => title, :content => content}
    end

    # Get the first pars of the first _count_ _urls_.
    # The pages are downloaded using the bot httputil service.
    # Returns an array of the first paragraphs fetched.
    # If (optional) _opts_ :message is specified, those paragraphs are
    # echoed as replies to the IRC message passed as _opts_ :message
    #
    def Utils.get_first_pars(urls, count, opts={})
      idx = 0
      msg = opts[:message]
      retval = Array.new
      while count > 0 and urls.length > 0
        url = urls.shift
        idx += 1

        begin
          info = Utils.get_html_info(URI.parse(url), opts)

          par = info[:content]
          retval.push(par)

          if par
            msg.reply "[#{idx}] #{par}", :overlong => :truncate if msg
            count -=1
          end
        rescue
          debug "Unable to retrieve #{url}: #{$!}"
          next
        end
      end
      return retval
    end

    # Returns a comma separated list except for the last element
    # which is joined in with specified conjunction
    #
    def Utils.comma_list(words, options={})
      defaults = { :join_with => ", ", :join_last_with => _(" and ") }
      opts = defaults.merge(options)

      if words.size < 2
        words.last
      else
        [words[0..-2].join(opts[:join_with]), words.last].join(opts[:join_last_with])
      end
    end

  end
end

Irc::Utils.bot = Irc::Bot::Plugins.manager.bot
