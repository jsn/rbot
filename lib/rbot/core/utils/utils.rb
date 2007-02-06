require 'net/http'
require 'uri'
require 'tempfile'

begin
  $we_have_html_entities_decoder = require 'htmlentities'
rescue LoadError
  $we_have_html_entities_decoder = false
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


module ::Irc

  # miscellaneous useful functions
  module Utils
    SEC_PER_MIN = 60
    SEC_PER_HR = SEC_PER_MIN * 60
    SEC_PER_DAY = SEC_PER_HR * 24
    SEC_PER_MNTH = SEC_PER_DAY * 30
    SEC_PER_YR = SEC_PER_MNTH * 12

    def Utils.secs_to_string_case(array, var, string, plural)
      case var
      when 1
        array << "1 #{string}"
      else
        array << "#{var} #{plural}"
      end
    end

    # turn a number of seconds into a human readable string, e.g
    # 2 days, 3 hours, 18 minutes, 10 seconds
    def Utils.secs_to_string(secs)
      ret = []
      years, secs = secs.divmod SEC_PER_YR
      secs_to_string_case(ret, years, "year", "years") if years > 0
      months, secs = secs.divmod SEC_PER_MNTH
      secs_to_string_case(ret, months, "month", "months") if months > 0
      days, secs = secs.divmod SEC_PER_DAY
      secs_to_string_case(ret, days, "day", "days") if days > 0
      hours, secs = secs.divmod SEC_PER_HR
      secs_to_string_case(ret, hours, "hour", "hours") if hours > 0
      mins, secs = secs.divmod SEC_PER_MIN
      secs_to_string_case(ret, mins, "minute", "minutes") if mins > 0
      secs_to_string_case(ret, secs, "second", "seconds") if secs > 0 or ret.empty?
      case ret.length
      when 0
        raise "Empty ret array!"
      when 1
        return ret.to_s
      else
        return [ret[0, ret.length-1].join(", ") , ret[-1]].join(" and ")
      end
    end


    def Utils.safe_exec(command, *args)
      IO.popen("-") {|p|
        if(p)
          return p.readlines.join("\n")
        else
          begin
            $stderr = $stdout
            exec(command, *args)
          rescue Exception => e
            puts "exec of #{command} led to exception: #{e.inspect}"
            Kernel::exit! 0
          end
          puts "exec of #{command} failed"
          Kernel::exit! 0
        end
      }
    end


    @@safe_save_dir = nil
    def Utils.set_safe_save_dir(str)
      @@safe_save_dir = str.dup
    end

    def Utils.safe_save(file)
      raise 'No safe save directory defined!' if @@safe_save_dir.nil?
      basename = File.basename(file)
      temp = Tempfile.new(basename,@@safe_save_dir)
      temp.binmode
      yield temp if block_given?
      temp.close
      File.rename(temp.path, file)
    end


    # returns a string containing the result of an HTTP GET on the uri
    def Utils.http_get(uristr, readtimeout=8, opentimeout=4)

      # ruby 1.7 or better needed for this (or 1.6 and debian unstable)
      Net::HTTP.version_1_2
      # (so we support the 1_1 api anyway, avoids problems)

      uri = URI.parse uristr
      query = uri.path
      if uri.query
        query += "?#{uri.query}"
      end

      proxy_host = nil
      proxy_port = nil
      if(ENV['http_proxy'] && proxy_uri = URI.parse(ENV['http_proxy']))
        proxy_host = proxy_uri.host
        proxy_port = proxy_uri.port
      end

      begin
        http = Net::HTTP.new(uri.host, uri.port, proxy_host, proxy_port)
        http.open_timeout = opentimeout
        http.read_timeout = readtimeout

        http.start {|http|
          resp = http.get(query)
          if resp.code == "200"
            return resp.body
          end
        }
      rescue => e
        # cheesy for now
        error "Utils.http_get exception: #{e.inspect}, while trying to get #{uristr}"
        return nil
      end
    end

    def Utils.decode_html_entities(str)
      if $we_have_html_entities_decoder
        return HTMLEntities.decode_entities(str)
      else
        str.gsub(/(&(.+?);)/) {
          symbol = $2
          # remove the 0-paddng from unicode integers
          if symbol =~ /#(.+)/
            symbol = "##{$1.to_i.to_s}"
          end

          # output the symbol's irc-translated character, or a * if it's unknown
          UNESCAPE_TABLE[symbol] || '*'
        }
      end
    end

    H1_REGEX = /<h1(?:\s+[^>]*)?>(.*?)<\/h1>/im
    PAR_REGEX = /<p(?:\s+[^>]*)?>.*?<\/p>/im
    # Try to grab and IRCify the first HTML par (<p> tag) in the given string.
    # If possible, grab the one after the first h1 heading
    def Utils.ircify_first_html_par(xml)
      header_found = xml.match(H1_REGEX)
      txt = String.new
      if header_found
        debug "Found header: #{header_found[1].inspect}"
        while txt.empty? 
          header_found = $'
          candidate = header_found[PAR_REGEX]
          break unless candidate
          txt = candidate.ircify_html
        end
      end
      # If we haven't found a first par yet, try to get it from the whole
      # document
      if txt.empty?
	header_found = xml
        while txt.empty? 
          candidate = header_found[PAR_REGEX]
          break unless candidate
          txt = candidate.ircify_html
          header_found = $'
        end
      end
      return txt
    end

    # Get the first pars of the first _count_ _urls_.
    # The pages are downloaded using an HttpUtil service passed as _opts_ :http_util,
    # and echoed as replies to the IRC message passed as _opts_ :message.
    #
    def Utils.get_first_pars(urls, count, opts={})
      idx = 0
      msg = opts[:message]
      while count > 0 and urls.length > 0
        url = urls.shift
        idx += 1

        # FIXME what happens if some big file is returned? We should share
        # code with the url plugin to only retrieve partial file content!
        xml = opts[:http_util].get_cached(url)
        if xml.nil?
          debug "Unable to retrieve #{url}"
          next
        end
        debug "Retrieved #{url}"
        debug "\t#{xml}"
        par = Utils.ircify_first_html_par(xml)
        if par.empty?
          debug "No first par found\n#{xml}"
          # FIXME only do this if the 'url' plugin is loaded
          # TODO even better, put the code here
          # par = @bot.plugins['url'].get_title_from_html(xml)
          next if par.empty?
        end
        msg.reply "[#{idx}] #{par}", :overlong => :truncate if msg
        count -=1
      end
    end


  end
end
