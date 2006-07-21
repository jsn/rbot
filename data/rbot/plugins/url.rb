require 'net/http'
require 'uri'
require 'cgi'

Url = Struct.new("Url", :channel, :nick, :time, :url)
TITLE_RE = /<\s*?title\s*?>(.+?)<\s*?\/title\s*?>/im

UNESCAPE_TABLE = {
    'raquo' => '>>',
    'quot' => '"',
    'micro' => 'u',
    'copy' => '(c)',
    'trade' => '(tm)',
    'reg' => '(R)',
    '#174' => '(R)',
    '#8220' => '"',
    '#8221' => '"',
    '#8212' => '--',
    '#39' => '\'',
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
    'lt' => '<',
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
    'amp' => '&',
    'AElig' => '\xc6',
    'oslash' => '\xf8',
    'acute' => '\xb4',
    'lceil' => '&#8968;',
    'laquo' => '\xab',
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

class UrlPlugin < Plugin
  BotConfig.register BotConfigIntegerValue.new('url.max_urls',
    :default => 100, :validate => Proc.new{|v| v > 0},
    :desc => "Maximum number of urls to store. New urls replace oldest ones.")
  BotConfig.register BotConfigBooleanValue.new('url.display_link_info',
    :default => false, 
    :desc => "Get the title of any links pasted to the channel and display it (also tells if the link is broken or the site is down)")
  
  def initialize
    super
    @registry.set_default(Array.new)
  end

  def help(plugin, topic="")
    "urls [<max>=4] => list <max> last urls mentioned in current channel, urls search [<max>=4] <regexp> => search for matching urls. In a private message, you must specify the channel to query, eg. urls <channel> [max], urls search <channel> [max] <regexp>"
  end

  def unescape_title(htmldata)
    # first pass -- let CGI try to attack it...
    htmldata = CGI::unescapeHTML htmldata
    
    # second pass -- destroy the remaining bits...
    htmldata.gsub(/(&(.+?);)/) {
        symbol = $2
        
        # remove the 0-paddng from unicode integers
        if symbol =~ /#(.+)/
            symbol = "##{$1.to_i.to_s}"
        end
        
        # output the symbol's irc-translated character, or a * if it's unknown
        UNESCAPE_TABLE[symbol] || '*'
    }
  end

  def get_title_from_html(pagedata)
    return unless TITLE_RE.match(pagedata)
    title = $1.strip.gsub(/\s*\n+\s*/, " ")
    title = unescape_title title
    title = title[0..255] if title.length > 255
    "[Link Info] title: #{title}"
  end

  def read_data_from_response(response, amount)
    
    amount_read = 0
    chunks = []
    
    response.read_body do |chunk|   # read body now
      
      amount_read += chunk.length
      
      if amount_read > amount
        amount_of_overflow = amount_read - amount
        chunk = chunk[0...-amount_of_overflow]
      end
      
      chunks << chunk

      break if amount_read >= amount
      
    end
    
    chunks.join('')
    
  end


  def get_title_for_url(uri_str, depth=10)
    # This god-awful mess is what the ruby http library has reduced me to.
    # Python's HTTP lib is so much nicer. :~(
    
    if depth == 0
        raise "Error: Maximum redirects hit."
    end
    
    debug "+ Getting #{uri_str}"
    url = URI.parse(uri_str)
    return if url.scheme !~ /https?/

    title = nil
    
    debug "+ connecting to #{url.host}:#{url.port}"
    http = @bot.httputil.get_proxy(url)
    http.start { |http|
      url.path = '/' if url.path == ''

      http.request_get(url.path, "User-Agent" => "Mozilla/4.0 (compatible; MSIE 6.0; Windows NT 5.1; SV1; .NET CLR 1.1.4322)") { |response|
        
        case response
          when Net::HTTPRedirection, Net::HTTPMovedPermanently then
            # call self recursively if this is a redirect
            redirect_to = response['location']  || './'
            debug "+ redirect location: #{redirect_to.inspect}"
            url = URI.join url.to_s, redirect_to
            debug "+ whee, redirecting to #{url.to_s}!"
            return get_title_for_url(url.to_s, depth-1)
          when Net::HTTPSuccess then
            if response['content-type'] =~ /^text\//
              # since the content is 'text/*' and is small enough to
              # be a webpage, retrieve the title from the page
              debug "+ getting #{url.request_uri}"
              data = read_data_from_response(response, 50000)
              return get_title_from_html(data)
            else
              # content doesn't have title, just display info.
              size = response['content-length'].gsub(/(\d)(?=\d{3}+(?:\.|$))(\d{3}\..*)?/,'\1,\2')
              return "[Link Info] type: #{response['content-type']}#{size ? ", size: #{size} bytes" : ""}"
            end
          when Net::HTTPClientError then
            return "[Link Info] Error getting link (#{response.code} - #{response.message})"
          when Net::HTTPServerError then
            return "[Link Info] Error getting link (#{response.code} - #{response.message})"
          else
            return nil
        end # end of "case response"
          
      } # end of request block
    } # end of http start block

    return title
    
  rescue SocketError => e
    return "[Link Info] Error connecting to site (#{e.message})"
  end

  def listen(m)
    return unless m.kind_of?(PrivMessage)
    return if m.address?
    # TODO support multiple urls in one line
    if m.message =~ /(f|ht)tps?:\/\//
      if m.message =~ /((f|ht)tps?:\/\/.*?)(?:\s+|$)/
        urlstr = $1
        list = @registry[m.target]

        if @bot.config['url.display_link_info']
          debug "Getting title for #{urlstr}..."
          title = get_title_for_url urlstr
          if title
            m.reply title
            debug "Title found!"
          else
            debug "Title not found!"
          end        
        end
    
        # check to see if this url is already listed
        return if list.find {|u| u.url == urlstr }
        
        url = Url.new(m.target, m.sourcenick, Time.new, urlstr)
        debug "#{list.length} urls so far"
        if list.length > @bot.config['url.max_urls']
          list.pop
        end
        debug "storing url #{url.url}"
        list.unshift url
        debug "#{list.length} urls now"
        @registry[m.target] = list
      end
    end
  end

  def urls(m, params)
    channel = params[:channel] ? params[:channel] : m.target
    max = params[:limit].to_i
    max = 10 if max > 10
    max = 1 if max < 1
    list = @registry[channel]
    if list.empty?
      m.reply "no urls seen yet for channel #{channel}"
    else
      list[0..(max-1)].each do |url|
        m.reply "[#{url.time.strftime('%Y/%m/%d %H:%M:%S')}] <#{url.nick}> #{url.url}"
      end
    end
  end

  def search(m, params)
    channel = params[:channel] ? params[:channel] : m.target
    max = params[:limit].to_i
    string = params[:string]
    max = 10 if max > 10
    max = 1 if max < 1
    regex = Regexp.new(string, Regexp::IGNORECASE)
    list = @registry[channel].find_all {|url|
      regex.match(url.url) || regex.match(url.nick)
    }
    if list.empty?
      m.reply "no matches for channel #{channel}"
    else
      list[0..(max-1)].each do |url|
        m.reply "[#{url.time.strftime('%Y/%m/%d %H:%M:%S')}] <#{url.nick}> #{url.url}"
      end
    end
  end
end
plugin = UrlPlugin.new
plugin.map 'urls search :channel :limit :string', :action => 'search',
                          :defaults => {:limit => 4},
                          :requirements => {:limit => /^\d+$/},
                          :public => false
plugin.map 'urls search :limit :string', :action => 'search',
                          :defaults => {:limit => 4},
                          :requirements => {:limit => /^\d+$/},
                          :private => false
plugin.map 'urls :channel :limit', :defaults => {:limit => 4},
                          :requirements => {:limit => /^\d+$/},
                          :public => false
plugin.map 'urls :limit', :defaults => {:limit => 4},
                          :requirements => {:limit => /^\d+$/},
                          :private => false
