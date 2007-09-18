#-- vim:sw=2:et
#++
#
# :title: rbot utilities provider
#
# Author:: Tom Gilbert <tom@linuxbrit.co.uk>
# Author:: Giuseppe "Oblomov" Bilotta <giuseppe.bilotta@gmail.com>
#
# Copyright:: (C) 2002-2006 Tom Gilbert
# Copyright:: (C) 2007 Giuseppe Bilotta
#
# TODO some of these Utils should be rewritten as extensions to the approriate
# standard Ruby classes and accordingly be moved to extends.rb

require 'tempfile'
require 'set'

# Try to load htmlentities, fall back to an HTML escape table.
begin
  require 'htmlentities'
rescue LoadError
  gems = nil
  begin
    gems = require 'rubygems'
  rescue LoadError
    gems = false
  end
  if gems
    retry
  else
    module ::Irc
      module Utils
        UNESCAPE_TABLE = {
    'laquo' => '<<',
    'raquo' => '>>',
    'quot' => '"',
    'apos' => '\'',
    'micro' => 'u',
    'copy' => '(c)',
    'trade' => '(tm)',
    'reg' => '(R)',
    '#174' => '(R)',
    '#8220' => '"',
    '#8221' => '"',
    '#8212' => '--',
    '#39' => '\'',
    'amp' => '&',
    'lt' => '<',
    'gt' => '>',
    'hellip' => '...',
    'nbsp' => ' ',
=begin
    # extras codes, for future use...
    'zwnj' => '&#8204;',
    'aring' => '\xe5',
    'gt' => '>',
    'yen' => '\xa5',
    'ograve' => '\xf2',
    'Chi' => '&#935;',
    'bull' => '&#8226;',
    'Egrave' => '\xc8',
    'Ntilde' => '\xd1',
    'upsih' => '&#978;',
    'Yacute' => '\xdd',
    'asymp' => '&#8776;',
    'radic' => '&#8730;',
    'otimes' => '&#8855;',
    'nabla' => '&#8711;',
    'aelig' => '\xe6',
    'oelig' => '&#339;',
    'equiv' => '&#8801;',
    'Psi' => '&#936;',
    'auml' => '\xe4',
    'circ' => '&#710;',
    'Acirc' => '\xc2',
    'Epsilon' => '&#917;',
    'Yuml' => '&#376;',
    'Eta' => '&#919;',
    'Icirc' => '\xce',
    'Upsilon' => '&#933;',
    'ndash' => '&#8211;',
    'there4' => '&#8756;',
    'Prime' => '&#8243;',
    'prime' => '&#8242;',
    'psi' => '&#968;',
    'Kappa' => '&#922;',
    'rsaquo' => '&#8250;',
    'Tau' => '&#932;',
    'darr' => '&#8595;',
    'ocirc' => '\xf4',
    'lrm' => '&#8206;',
    'zwj' => '&#8205;',
    'cedil' => '\xb8',
    'Ecirc' => '\xca',
    'not' => '\xac',
    'AElig' => '\xc6',
    'oslash' => '\xf8',
    'acute' => '\xb4',
    'lceil' => '&#8968;',
    'shy' => '\xad',
    'rdquo' => '&#8221;',
    'ge' => '&#8805;',
    'Igrave' => '\xcc',
    'Ograve' => '\xd2',
    'euro' => '&#8364;',
    'dArr' => '&#8659;',
    'sdot' => '&#8901;',
    'nbsp' => '\xa0',
    'lfloor' => '&#8970;',
    'lArr' => '&#8656;',
    'Auml' => '\xc4',
    'larr' => '&#8592;',
    'Atilde' => '\xc3',
    'Otilde' => '\xd5',
    'szlig' => '\xdf',
    'clubs' => '&#9827;',
    'diams' => '&#9830;',
    'agrave' => '\xe0',
    'Ocirc' => '\xd4',
    'Iota' => '&#921;',
    'Theta' => '&#920;',
    'Pi' => '&#928;',
    'OElig' => '&#338;',
    'Scaron' => '&#352;',
    'frac14' => '\xbc',
    'egrave' => '\xe8',
    'sub' => '&#8834;',
    'iexcl' => '\xa1',
    'frac12' => '\xbd',
    'sbquo' => '&#8218;',
    'ordf' => '\xaa',
    'sum' => '&#8721;',
    'prop' => '&#8733;',
    'Uuml' => '\xdc',
    'ntilde' => '\xf1',
    'sup' => '&#8835;',
    'theta' => '&#952;',
    'prod' => '&#8719;',
    'nsub' => '&#8836;',
    'hArr' => '&#8660;',
    'rlm' => '&#8207;',
    'THORN' => '\xde',
    'infin' => '&#8734;',
    'yuml' => '\xff',
    'Mu' => '&#924;',
    'le' => '&#8804;',
    'Eacute' => '\xc9',
    'thinsp' => '&#8201;',
    'ecirc' => '\xea',
    'bdquo' => '&#8222;',
    'Sigma' => '&#931;',
    'fnof' => '&#402;',
    'Aring' => '\xc5',
    'tilde' => '&#732;',
    'frac34' => '\xbe',
    'emsp' => '&#8195;',
    'mdash' => '&#8212;',
    'uarr' => '&#8593;',
    'permil' => '&#8240;',
    'Ugrave' => '\xd9',
    'rarr' => '&#8594;',
    'Agrave' => '\xc0',
    'chi' => '&#967;',
    'forall' => '&#8704;',
    'eth' => '\xf0',
    'rceil' => '&#8969;',
    'iuml' => '\xef',
    'gamma' => '&#947;',
    'lambda' => '&#955;',
    'harr' => '&#8596;',
    'rang' => '&#9002;',
    'xi' => '&#958;',
    'dagger' => '&#8224;',
    'divide' => '\xf7',
    'Ouml' => '\xd6',
    'image' => '&#8465;',
    'alefsym' => '&#8501;',
    'igrave' => '\xec',
    'otilde' => '\xf5',
    'Oacute' => '\xd3',
    'sube' => '&#8838;',
    'alpha' => '&#945;',
    'frasl' => '&#8260;',
    'ETH' => '\xd0',
    'lowast' => '&#8727;',
    'Nu' => '&#925;',
    'plusmn' => '\xb1',
    'Euml' => '\xcb',
    'real' => '&#8476;',
    'sup1' => '\xb9',
    'sup2' => '\xb2',
    'sup3' => '\xb3',
    'Oslash' => '\xd8',
    'Aacute' => '\xc1',
    'cent' => '\xa2',
    'oline' => '&#8254;',
    'Beta' => '&#914;',
    'perp' => '&#8869;',
    'Delta' => '&#916;',
    'loz' => '&#9674;',
    'pi' => '&#960;',
    'iota' => '&#953;',
    'empty' => '&#8709;',
    'euml' => '\xeb',
    'brvbar' => '\xa6',
    'iacute' => '\xed',
    'para' => '\xb6',
    'micro' => '\xb5',
    'cup' => '&#8746;',
    'weierp' => '&#8472;',
    'uuml' => '\xfc',
    'part' => '&#8706;',
    'icirc' => '\xee',
    'delta' => '&#948;',
    'omicron' => '&#959;',
    'upsilon' => '&#965;',
    'Iuml' => '\xcf',
    'Lambda' => '&#923;',
    'Xi' => '&#926;',
    'kappa' => '&#954;',
    'ccedil' => '\xe7',
    'Ucirc' => '\xdb',
    'cap' => '&#8745;',
    'mu' => '&#956;',
    'scaron' => '&#353;',
    'lsquo' => '&#8216;',
    'isin' => '&#8712;',
    'Zeta' => '&#918;',
    'supe' => '&#8839;',
    'deg' => '\xb0',
    'and' => '&#8743;',
    'tau' => '&#964;',
    'pound' => '\xa3',
    'hellip' => '&#8230;',
    'curren' => '\xa4',
    'int' => '&#8747;',
    'ucirc' => '\xfb',
    'rfloor' => '&#8971;',
    'ensp' => '&#8194;',
    'crarr' => '&#8629;',
    'ugrave' => '\xf9',
    'notin' => '&#8713;',
    'exist' => '&#8707;',
    'uArr' => '&#8657;',
    'cong' => '&#8773;',
    'Dagger' => '&#8225;',
    'oplus' => '&#8853;',
    'times' => '\xd7',
    'atilde' => '\xe3',
    'piv' => '&#982;',
    'ni' => '&#8715;',
    'Phi' => '&#934;',
    'lsaquo' => '&#8249;',
    'Uacute' => '\xda',
    'Omicron' => '&#927;',
    'ang' => '&#8736;',
    'ne' => '&#8800;',
    'iquest' => '\xbf',
    'eta' => '&#951;',
    'yacute' => '\xfd',
    'Rho' => '&#929;',
    'uacute' => '\xfa',
    'Alpha' => '&#913;',
    'zeta' => '&#950;',
    'Omega' => '&#937;',
    'nu' => '&#957;',
    'sim' => '&#8764;',
    'sect' => '\xa7',
    'phi' => '&#966;',
    'sigmaf' => '&#962;',
    'macr' => '\xaf',
    'minus' => '&#8722;',
    'Ccedil' => '\xc7',
    'ordm' => '\xba',
    'epsilon' => '&#949;',
    'beta' => '&#946;',
    'rArr' => '&#8658;',
    'rho' => '&#961;',
    'aacute' => '\xe1',
    'eacute' => '\xe9',
    'omega' => '&#969;',
    'middot' => '\xb7',
    'Gamma' => '&#915;',
    'Iacute' => '\xcd',
    'lang' => '&#9001;',
    'spades' => '&#9824;',
    'rsquo' => '&#8217;',
    'uml' => '\xa8',
    'thorn' => '\xfe',
    'ouml' => '\xf6',
    'thetasym' => '&#977;',
    'or' => '&#8744;',
    'raquo' => '\xbb',
    'acirc' => '\xe2',
    'ldquo' => '&#8220;',
    'hearts' => '&#9829;',
    'sigma' => '&#963;',
    'oacute' => '\xf3',
=end
        }
      end
    end
  end
end

begin
  require 'htmlentities'
rescue LoadError
  gems = nil
  begin
    gems = require 'rubygems'
  rescue LoadError
    gems = false
  end
  if gems
    retry
  else
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
        AFTER_PAR1_REGEX = /<\w+\s+[^>]*(?:body|message|text)[^>]*>.*?<\/?(?:p|div|html|body|table|td|tr)(?:\s+[^>]*)?>/im

        # At worst, we can try stuff which is comprised between two <br>
        AFTER_PAR2_REGEX = /<br(?:\s+[^>]*)?\/?>.*?<\/?(?:br|p|div|html|body|table|td|tr)(?:\s+[^>]*)?\/?>/im
      end
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
      @@safe_save_dir = "#{@@bot.botclass}/safe_save"
    end


    # Seconds per minute
    SEC_PER_MIN = 60
    # Seconds per hour
    SEC_PER_HR = SEC_PER_MIN * 60
    # Seconds per day
    SEC_PER_DAY = SEC_PER_HR * 24
    # Seconds per (30-day) month
    SEC_PER_MNTH = SEC_PER_DAY * 30
    # Second per (30*12 = 360 day) year
    SEC_PER_YR = SEC_PER_MNTH * 12

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
        return ret.to_s
      else
        return [ret[0, ret.length-1].join(", ") , ret[-1]].join(_(" and "))
      end
    end


    # Execute an external program, returning a String obtained by redirecting
    # the program's standards errors and output 
    #
    def Utils.safe_exec(command, *args)
      IO.popen("-") { |p|
        if p
          return p.readlines.join("\n")
        else
          begin
            $stderr.reopen($stdout)
            exec(command, *args)
          rescue Exception => e
            puts "exec of #{command} led to exception: #{e.pretty_inspect}"
            Kernel::exit! 0
          end
          puts "exec of #{command} failed"
          Kernel::exit! 0
        end
      }
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
    def Utils.decode_html_entities(str)
      if defined? ::HTMLEntities
        return HTMLEntities.decode_entities(str)
      else
        str.gsub(/(&(.+?);)/) {
          symbol = $2
          # remove the 0-paddng from unicode integers
          if symbol =~ /#(.+)/
            symbol = "##{$1.to_i.to_s}"
          end

          # output the symbol's irc-translated character, or a * if it's unknown
          UNESCAPE_TABLE[symbol] || [symbol[/\d+/].to_i].pack("U") rescue '*'
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

      debug doc.inspect

      strip = opts[:strip]
      strip = Regexp.new(/^#{Regexp.escape(strip)}/) if strip.kind_of?(String)

      min_spaces = opts[:min_spaces] || 8
      min_spaces = 0 if min_spaces < 0

      txt = String.new

      h = %w{h1 h2 h3 h4 h5 h6}
      p = %w{p}
      ar = []
      h.each { |hx|
        p.each { |px|
          ar << "#{hx}~#{px}"
        }
      }
      h_p_css = ar.join("|")
      debug "css search: #{h_p_css}"

      pre_h = pars = by_span = nil

      while true
        debug "Minimum number of spaces: #{min_spaces}"

        # Initial attempt: <p> that follows <h\d>
        pre_h = doc/h_p_css if pre_h.nil?
        debug "Hx: found: #{pre_h.pretty_inspect}"
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
        # we don't need
        if by_span.nil?
          by_span = Hpricot::Elements[]
          pre_pars = doc/"div|span|td|tr|tbody|table"
          pre_pars.each { |el|
            by_span.push el if el[:class] =~ /body|message|text/i
          }
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
      xml = xml_org.gsub(/<!--.*?-->/m, '').gsub(/<script(?:\s+[^>]*)?>.*?<\/script>/im, "").gsub(/<style(?:\s+[^>]*)?>.*?<\/style>/im, "")

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
        if doc.fragment and not doc.fragment.empty?
          opts[:uri_fragment] ||= doc.fragment
        end
        ret = Hash.new
        @@bot.httputil.get_response(doc) { |resp|
          ret = Utils.get_resp_html_info(resp, opts)
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
    # Currently, the only accepted option (in _opts_) is
    # uri_fragment:: the URI fragment of the original request
    #
    # Returns a Hash with the following keys:
    # title:: the title of the document (if any)
    # content:: the first paragraph of the document (if any)
    # headers::
    #   the headers of the Net::HTTPResponse. The value is
    #   a Hash whose keys are lowercase forms of the HTTP
    #   header fields, and whose values are Arrays.
    #
    def Utils.get_resp_html_info(resp, opts={})
      ret = Hash.new
      case resp
      when Net::HTTPSuccess
        ret[:headers] = resp.to_hash

        if resp['content-type'] =~ /^text\/|(?:x|ht)ml/
          partial = resp.partial_body(@@bot.config['http.info_bytes'])
          ret.merge!(Utils.get_string_html_info(partial, opts))
        end
        return ret
      else
        raise UrlLinkError, "getting link (#{resp.code} - #{resp.message})"
      end
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
      txt = text.dup
      title = txt.ircify_html_title
      if frag = opts[:uri_fragment] and not frag.empty?
        fragreg = /.*?<a\s+[^>]*name=["']?#{frag}["']?.*?>/im
        txt.sub!(fragreg,'')
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

  end
end

Irc::Utils.bot = Irc::Bot::Plugins.manager.bot
