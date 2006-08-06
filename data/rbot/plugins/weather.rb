# This is nasty-ass. I hate writing parsers.
class Metar
  attr_reader :decoded
  attr_reader :input
  attr_reader :date
  attr_reader :nodata
  def initialize(string)
    str = nil
    @nodata = false
    string.each_line {|l|
      if str == nil
        # grab first line (date)
        @date = l.chomp.strip
        str = ""
      else
        if(str == "")
          str = l.chomp.strip
        else
          str += " " + l.chomp.strip
        end
      end
    }
    if @date && @date =~ /^(\d+)\/(\d+)\/(\d+) (\d+):(\d+)$/
      # 2002/02/26 05:00
      @date = Time.gm($1, $2, $3, $4, $5, 0)
    else
      @date = Time.now
    end
    @input = str.chomp
    @cloud_layers = 0
    @cloud_coverage = {
      'SKC' => '0',
      'CLR' => '0',
      'VV'  => '8/8',
      'FEW' => '1/8 - 2/8',
      'SCT' => '3/8 - 4/8',
      'BKN' => '5/8 - 7/8',
      'OVC' => '8/8'
    }
    @wind_dir_texts = [
      'North',
      'North/Northeast',
      'Northeast',
      'East/Northeast',
      'East',
      'East/Southeast',
      'Southeast',
      'South/Southeast',
      'South',
      'South/Southwest',
      'Southwest',
      'West/Southwest',
      'West',
      'West/Northwest',
      'Northwest',
      'North/Northwest',
      'North'
    ]
    @wind_dir_texts_short = [
      'N',
      'N/NE',
      'NE',
      'E/NE',
      'E',
      'E/SE',
      'SE',
      'S/SE',
      'S',
      'S/SW',
      'SW',
      'W/SW',
      'W',
      'W/NW',
      'NW',
      'N/NW',
      'N'
    ]
    @weather_array = {
      'MI' => 'Mild ',
      'PR' => 'Partial ',
      'BC' => 'Patches ',
      'DR' => 'Low Drifting ',
      'BL' => 'Blowing ',
      'SH' => 'Shower(s) ',
      'TS' => 'Thunderstorm ',
      'FZ' => 'Freezing',
      'DZ' => 'Drizzle ',
      'RA' => 'Rain ',
      'SN' => 'Snow ',
      'SG' => 'Snow Grains ',
      'IC' => 'Ice Crystals ',
      'PE' => 'Ice Pellets ',
      'GR' => 'Hail ',
      'GS' => 'Small Hail and/or Snow Pellets ',
      'UP' => 'Unknown ',
      'BR' => 'Mist ',
      'FG' => 'Fog ',
      'FU' => 'Smoke ',
      'VA' => 'Volcanic Ash ',
      'DU' => 'Widespread Dust ',
      'SA' => 'Sand ',
      'HZ' => 'Haze ',
      'PY' => 'Spray',
      'PO' => 'Well-Developed Dust/Sand Whirls ',
      'SQ' => 'Squalls ',
      'FC' => 'Funnel Cloud Tornado Waterspout ',
      'SS' => 'Sandstorm/Duststorm '
    }
    @cloud_condition_array = {
      'SKC' => 'clear',
      'CLR' => 'clear',
      'VV'  => 'vertical visibility',
      'FEW' => 'a few',
      'SCT' => 'scattered',
      'BKN' => 'broken',
      'OVC' => 'overcast'
    }
    @strings = {
      'mm_inches'             => '%s mm (%s inches)',
      'precip_a_trace'        => 'a trace',
      'precip_there_was'      => 'There was %s of precipitation ',
      'sky_str_format1'       => 'There were %s at a height of %s meters (%s feet)',
      'sky_str_clear'         => 'The sky was clear',
      'sky_str_format2'       => ', %s at a height of %s meter (%s feet) and %s at a height of %s meters (%s feet)',
      'sky_str_format3'       => ' and %s at a height of %s meters (%s feet)',
      'clouds'                => ' clouds',
      'clouds_cb'             => ' cumulonimbus clouds',
      'clouds_tcu'            => ' towering cumulus clouds',
      'visibility_format'     => 'The visibility was %s kilometers (%s miles).',
      'wind_str_format1'      => 'blowing at a speed of %s meters per second (%s miles per hour)',
      'wind_str_format2'      => ', with gusts to %s meters per second (%s miles per hour),',
      'wind_str_format3'      => ' from the %s',
      'wind_str_calm'         => 'calm',
      'precip_last_hour'      => 'in the last hour. ',
      'precip_last_6_hours'   => 'in the last 3 to 6 hours. ',
      'precip_last_24_hours'  => 'in the last 24 hours. ',
      'precip_snow'           => 'There is %s mm (%s inches) of snow on the ground. ',
      'temp_min_max_6_hours'  => 'The maximum and minimum temperatures over the last 6 hours were %s and %s degrees Celsius (%s and %s degrees Fahrenheit).',
      'temp_max_6_hours'      => 'The maximum temperature over the last 6 hours was %s degrees Celsius (%s degrees Fahrenheit). ',
      'temp_min_6_hours'      => 'The minimum temperature over the last 6 hours was %s degrees Celsius (%s degrees Fahrenheit). ',
      'temp_min_max_24_hours' => 'The maximum and minimum temperatures over the last 24 hours were %s and %s degrees Celsius (%s and %s degrees Fahrenheit). ',
      'light'                 => 'Light ',
      'moderate'              => 'Moderate ',
      'heavy'                 => 'Heavy ',
      'mild'                  => 'Mild ',
      'nearby'                => 'Nearby ',
      'current_weather'       => 'Current weather is %s. ',
      'pretty_print_metar'    => '%s on %s, the wind was %s at %s. The temperature was %s degrees Celsius (%s degrees Fahrenheit), and the pressure was %s hPa (%s inHg). The relative humidity was %s%%. %s %s %s %s %s'
    }

    parse
  end

  def store_speed(value, windunit, meterspersec, knots, milesperhour)
    # Helper function to convert and store speed based on unit.
    # &$meterspersec, &$knots and &$milesperhour are passed on
    # reference
    if (windunit == 'KT')
      # The windspeed measured in knots:
      @decoded[knots] = sprintf("%.2f", value)
      # The windspeed measured in meters per second, rounded to one decimal place:
      @decoded[meterspersec] = sprintf("%.2f", value.to_f * 0.51444)
      # The windspeed measured in miles per hour, rounded to one decimal place: */
      @decoded[milesperhour] = sprintf("%.2f", value.to_f * 1.1507695060844667)
    elsif (windunit == 'MPS')
      # The windspeed measured in meters per second:
      @decoded[meterspersec] = sprintf("%.2f", value)
      # The windspeed measured in knots, rounded to one decimal place:
      @decoded[knots] = sprintf("%.2f", value.to_f / 0.51444)
      #The windspeed measured in miles per hour, rounded to one decimal place:
      @decoded[milesperhour] = sprintf("%.1f", value.to_f / 0.51444 * 1.1507695060844667)
    elsif (windunit == 'KMH')
      # The windspeed measured in kilometers per hour:
      @decoded[meterspersec] = sprintf("%.1f", value.to_f * 1000 / 3600)
      @decoded[knots] = sprintf("%.1f", value.to_f * 1000 / 3600 / 0.51444)
      # The windspeed measured in miles per hour, rounded to one decimal place:
      @decoded[milesperhour] = sprintf("%.1f", knots.to_f * 1.1507695060844667)
    end
  end
  
  def parse
    @decoded = Hash.new
    puts @input
    @input.split(" ").each {|part|
      if (part == 'METAR')
        # Type of Report: METAR
        @decoded['type'] = 'METAR'
      elsif (part == 'SPECI')
        # Type of Report: SPECI
        @decoded['type'] = 'SPECI'
      elsif (part == 'AUTO')
        # Report Modifier: AUTO
        @decoded['report_mod'] = 'AUTO'
      elsif (part == 'NIL')
        @nodata = true
      elsif (part =~ /^\S{4}$/ && ! (@decoded.has_key?('station')))
        # Station Identifier
        @decoded['station'] = part
      elsif (part =~ /([0-9]{2})([0-9]{2})([0-9]{2})Z/)
        # ignore this bit, it's useless without month/year. some of these
        # things are hideously out of date.
        # now = Time.new
        # time = Time.gm(now.year, now.month, $1, $2, $3, 0)
        # Date and Time of Report
        # @decoded['time'] = time
      elsif (part == 'COR')
        # Report Modifier: COR
        @decoded['report_mod'] = 'COR'
      elsif (part =~ /([0-9]{3}|VRB)([0-9]{2,3}).*(KT|MPS|KMH)/)
        # Wind Group
        windunit = $3
        # now do ereg to get the actual values
        part =~ /([0-9]{3}|VRB)([0-9]{2,3})((G[0-9]{2,3})?#{windunit})/
        if ($1 == 'VRB')
          @decoded['wind_deg'] = 'variable directions'
          @decoded['wind_dir_text'] = 'variable directions'
          @decoded['wind_dir_text_short'] = 'VAR'
        else
          @decoded['wind_deg'] = $1
          @decoded['wind_dir_text'] = @wind_dir_texts[($1.to_i/22.5).round]
          @decoded['wind_dir_text_short'] = @wind_dir_texts_short[($1.to_i/22.5).round]
        end
        store_speed($2, windunit,
                    'wind_meters_per_second',
                    'wind_knots',
                    'wind_miles_per_hour')

        if ($4 != nil)
          # We have a report with information about the gust.
          # First we have the gust measured in knots
    if ($4 =~ /G([0-9]{2,3})/)
          store_speed($1,windunit,
                      'wind_gust_meters_per_second',
                      'wind_gust_knots',
                      'wind_gust_miles_per_hour')
    end
        end
      elsif (part =~ /([0-9]{3})V([0-9]{3})/)
        #  Variable wind-direction
        @decoded['wind_var_beg'] = $1
        @decoded['wind_var_end'] = $2
      elsif (part == "9999")
        # A strange value. When you look at other pages you see it
        # interpreted like this (where I use > to signify 'Greater
        # than'):
        @decoded['visibility_miles'] = '>7';
        @decoded['visibility_km']    = '>11.3';
      elsif (part =~ /^([0-9]{4})$/)
        # Visibility in meters (4 digits only)
        # The visibility measured in kilometers, rounded to one decimal place.
        @decoded['visibility_km'] = sprintf("%.1f", $1.to_i / 1000)
        # The visibility measured in miles, rounded to one decimal place.
        @decoded['visibility_miles'] = sprintf("%.1f", $1.to_i / 1000 / 1.609344)
      elsif (part =~ /^[0-9]$/)
        # Temp Visibility Group, single digit followed by space
        @decoded['temp_visibility_miles'] = part
      elsif (@decoded['temp_visibility_miles'] && (@decoded['temp_visibility_miles']+' '+part) =~ /^M?(([0-9]?)[ ]?([0-9])(\/?)([0-9]*))SM$/)
        # Visibility Group
        if ($4 == '/')
          vis_miles = $2.to_i + $3.to_i/$5.to_i
        else
          vis_miles = $1.to_i;
        end
        if (@decoded['temp_visibility_miles'][0] == 'M')
          # The visibility measured in miles, prefixed with < to indicate 'Less than'
          @decoded['visibility_miles'] = '<' + sprintf("%.1f", vis_miles)
          # The visibility measured in kilometers. The value is rounded
          # to one decimal place, prefixed with < to indicate 'Less than' */
          @decoded['visibility_km']    = '<' . sprintf("%.1f", vis_miles * 1.609344)
        else
          # The visibility measured in mile.s */
          @decoded['visibility_miles'] = sprintf("%.1f", vis_miles)
          # The visibility measured in kilometers, rounded to one decimal place.
          @decoded['visibility_km']    = sprintf("%.1f", vis_miles * 1.609344)
        end
      elsif (part =~ /^(-|\+|VC|MI)?(TS|SH|FZ|BL|DR|BC|PR|RA|DZ|SN|SG|GR|GS|PE|IC|UP|BR|FG|FU|VA|DU|SA|HZ|PY|PO|SQ|FC|SS|DS)+$/)
        # Current weather-group
        @decoded['weather'] = '' unless @decoded.has_key?('weather')
        if (part[0].chr == '-')
          # A light phenomenon
          @decoded['weather'] += @strings['light']
          part = part[1,part.length]
        elsif (part[0].chr == '+')
          # A heavy phenomenon
          @decoded['weather'] += @strings['heavy']
          part = part[1,part.length]
        elsif (part[0,2] == 'VC')
          # Proximity Qualifier
          @decoded['weather'] += @strings['nearby']
          part = part[2,part.length]
        elsif (part[0,2] == 'MI')
          @decoded['weather'] += @strings['mild']
          part = part[2,part.length]
        else
          # no intensity code => moderate phenomenon
          @decoded['weather'] += @strings['moderate']
        end
        
        while (part && bite = part[0,2]) do
          # Now we take the first two letters and determine what they
          # mean. We append this to the variable so that we gradually
          # build up a phrase.

          @decoded['weather'] += @weather_array[bite]
          # Here we chop off the two first letters, so that we can take
          # a new bite at top of the while-loop.
          part = part[2,-1]
        end
      elsif (part =~ /(SKC|CLR)/)
        # Cloud-layer-group.
        # There can be up to three of these groups, so we store them as
        # cloud_layer1, cloud_layer2 and cloud_layer3.
        
        @cloud_layers += 1;
        # Again we have to translate the code-characters to a
        # meaningful string.
        @decoded['cloud_layer'+ (@cloud_layers.to_s) +'_condition']  = @cloud_condition_array[$1]
        @decoded['cloud_layer'+ (@cloud_layers.to_s) +'_coverage'] = @cloud_coverage[$1]
      elsif (part =~ /^(VV|FEW|SCT|BKN|OVC)([0-9]{3})(CB|TCU)?$/)
        # We have found (another) a cloud-layer-group. There can be up
        # to three of these groups, so we store them as cloud_layer1,
        # cloud_layer2 and cloud_layer3.
        @cloud_layers += 1;
        # Again we have to translate the code-characters to a meaningful string.
        if ($3 == 'CB')
          # cumulonimbus (CB) clouds were observed. */
          @decoded['cloud_layer'+ (@cloud_layers.to_s) +'_condition'] =
                      @cloud_condition_array[$1] + @strings['clouds_cb']
        elsif ($3 == 'TCU')
          # towering cumulus (TCU) clouds were observed.
          @decoded['cloud_layer'+ (@cloud_layers.to_s) +'_condition'] =
                      @cloud_condition_array[$1] + @strings['clouds_tcu']
        else
          @decoded['cloud_layer'+ (@cloud_layers.to_s) +'_condition'] =
                      @cloud_condition_array[$1] + @strings['clouds']
        end
        @decoded['cloud_layer'+ (@cloud_layers.to_s) +'_coverage'] = @cloud_coverage[$1]
        @decoded['cloud_layer'+ (@cloud_layers.to_s) +'_altitude_ft'] = $2.to_i * 100
        @decoded['cloud_layer'+ (@cloud_layers.to_s) +'_altitude_m']  = ($2.to_f * 30.48).round
      elsif (part =~ /^T([0-9]{4})$/)
        store_temp($1,'temp_c','temp_f')
      elsif (part =~ /^T?(M?[0-9]{2})\/(M?[0-9\/]{1,2})?$/)
        # Temperature/Dew Point Group
        # The temperature and dew-point measured in Celsius.
        @decoded['temp_c'] = sprintf("%d", $1.tr('M', '-'))
        if $2 == "//" || !$2
          @decoded['dew_c'] = 0
        else
          @decoded['dew_c'] = sprintf("%.1f", $2.tr('M', '-'))
        end
        # The temperature and dew-point measured in Fahrenheit, rounded to
        # the nearest degree.
        @decoded['temp_f'] = ((@decoded['temp_c'].to_f * 9 / 5) + 32).round
        @decoded['dew_f']  = ((@decoded['dew_c'].to_f * 9 / 5) + 32).round
      elsif(part =~ /A([0-9]{4})/)
        # Altimeter
        # The pressure measured in inHg
        @decoded['altimeter_inhg'] = sprintf("%.2f", $1.to_i/100)
        # The pressure measured in mmHg, hPa and atm
        @decoded['altimeter_mmhg'] = sprintf("%.1f", $1.to_f * 0.254)
        @decoded['altimeter_hpa']  = sprintf("%d", ($1.to_f * 0.33863881578947).to_i)
        @decoded['altimeter_atm']  = sprintf("%.3f", $1.to_f * 3.3421052631579e-4)
      elsif(part =~ /Q([0-9]{4})/)
        # Altimeter
        # This is strange, the specification doesnt say anything about
        # the Qxxxx-form, but it's in the METARs.
        # The pressure measured in hPa
        @decoded['altimeter_hpa']  = sprintf("%d", $1.to_i)
        # The pressure measured in mmHg, inHg and atm
        @decoded['altimeter_mmhg'] = sprintf("%.1f", $1.to_f * 0.7500616827)
        @decoded['altimeter_inhg'] = sprintf("%.2f", $1.to_f * 0.0295299875)
        @decoded['altimeter_atm']  = sprintf("%.3f", $1.to_f * 9.869232667e-4)
      elsif (part =~ /^T([0-9]{4})([0-9]{4})/)
        # Temperature/Dew Point Group, coded to tenth of degree.
        # The temperature and dew-point measured in Celsius.
        store_temp($1,'temp_c','temp_f')
        store_temp($2,'dew_c','dew_f')
      elsif (part =~ /^1([0-9]{4}$)/)
        # 6 hour maximum temperature Celsius, coded to tenth of degree
        store_temp($1,'temp_max6h_c','temp_max6h_f')
      elsif (part =~ /^2([0-9]{4}$)/)
        # 6 hour minimum temperature Celsius, coded to tenth of degree
        store_temp($1,'temp_min6h_c','temp_min6h_f')
      elsif (part =~ /^4([0-9]{4})([0-9]{4})$/)
        # 24 hour maximum and minimum temperature Celsius, coded to
        # tenth of degree
        store_temp($1,'temp_max24h_c','temp_max24h_f')
        store_temp($2,'temp_min24h_c','temp_min24h_f')
      elsif (part =~ /^P([0-9]{4})/)
        # Precipitation during last hour in hundredths of an inch
        # (store as inches)
        @decoded['precip_in'] = sprintf("%.2f", $1.to_f/100)
        @decoded['precip_mm'] = sprintf("%.2f", $1.to_f * 0.254)
      elsif (part =~ /^6([0-9]{4})/)
        # Precipitation during last 3 or 6 hours in hundredths of an
        # inch  (store as inches)
        @decoded['precip_6h_in'] = sprintf("%.2f", $1.to_f/100)
        @decoded['precip_6h_mm'] = sprintf("%.2f", $1.to_f * 0.254)
      elsif (part =~ /^7([0-9]{4})/)
        # Precipitation during last 24 hours in hundredths of an inch
        # (store as inches)
        @decoded['precip_24h_in'] = sprintf("%.2f", $1.to_f/100)
        @decoded['precip_24h_mm'] = sprintf("%.2f", $1.to_f * 0.254)
      elsif(part =~ /^4\/([0-9]{3})/)
        # Snow depth in inches
        @decoded['snow_in'] = sprintf("%.2f", $1);
        @decoded['snow_mm'] = sprintf("%.2f", $1.to_f * 25.4)
      else
        # If we couldn't match the group, we assume that it was a
        # remark.
        @decoded['remarks'] = '' unless @decoded.has_key?("remarks")
        @decoded['remarks'] += ' ' + part;
      end
    }
    
    # Relative humidity
    # p @decoded['dew_c'] # 11.0
    # p @decoded['temp_c'] # 21.0
    # => 56.1
    @decoded['rel_humidity'] = sprintf("%.1f",100 * 
      (6.11 * (10.0**(7.5 * @decoded['dew_c'].to_f / (237.7 + @decoded['dew_c'].to_f)))) / (6.11 * (10.0 ** (7.5 * @decoded['temp_c'].to_f / (237.7 + @decoded['temp_c'].to_f))))) if @decoded.has_key?('dew_c')
  end

  def store_temp(temp,temp_cname,temp_fname)
    # Given a numerical temperature temp in Celsius, coded to tenth of
    # degree, store in @decoded[temp_cname], convert to Fahrenheit
    # and store in @decoded[temp_fname]
    # Note: temp is converted to negative if temp > 100.0 (See
    # Federal Meteorological Handbook for groups T, 1, 2 and 4)

    # Temperature measured in Celsius, coded to tenth of degree
    temp = temp.to_f/10
    if (temp >100.0) 
        # first digit = 1 means minus temperature
        temp = -(temp - 100.0)
    end
    @decoded[temp_cname] = sprintf("%.1f", temp)
    # The temperature in Fahrenheit.
    @decoded[temp_fname] = sprintf("%.1f", (temp * 9 / 5) + 32)        
  end

    def pretty_print_precip(precip_mm, precip_in)
      # Returns amount if $precip_mm > 0, otherwise "trace" (see Federal
      # Meteorological Handbook No. 1 for code groups P, 6 and 7) used in
      # several places, so standardized in one function.
      if (precip_mm.to_i > 0)
        amount = sprintf(@strings['mm_inches'], precip_mm, precip_in)
      else
        amount = @strings['a_trace']
      end
      return sprintf(@strings['precip_there_was'], amount)
  end

  def pretty_print
    if @nodata
      return "The weather stored for #{@decoded['station']} consists of the string 'NIL' :("
    end

    ["temp_c", "altimeter_hpa"].each {|key|
      if !@decoded.has_key?(key)
        return "The weather stored for #{@decoded['station']} could not be parsed (#{@input})"
      end
    }
    
    mins_old = ((Time.now - @date.to_i).to_f/60).round
    if (mins_old <= 60)
      weather_age = mins_old.to_s + " minutes ago,"
    elsif (mins_old <= 60 * 25)
      weather_age = (mins_old / 60).to_s + " hours, "
      weather_age += (mins_old % 60).to_s + " minutes ago,"
    else
      # return "The weather stored for #{@decoded['station']} is hideously out of date :( (Last update #{@date})"
      weather_age = "The weather stored for #{@decoded['station']} is hideously out of date :( here it is anyway:"
    end
    
    if(@decoded.has_key?("cloud_layer1_altitude_ft"))
      sky_str = sprintf(@strings['sky_str_format1'],
                        @decoded["cloud_layer1_condition"],
                        @decoded["cloud_layer1_altitude_m"],
                        @decoded["cloud_layer1_altitude_ft"])
    else
      sky_str = @strings['sky_str_clear']
    end

    if(@decoded.has_key?("cloud_layer2_altitude_ft"))
      if(@decoded.has_key?("cloud_layer3_altitude_ft"))
        sky_str += sprintf(@strings['sky_str_format2'],
                          @decoded["cloud_layer2_condition"],
                          @decoded["cloud_layer2_altitude_m"],
                          @decoded["cloud_layer2_altitude_ft"],
                          @decoded["cloud_layer3_condition"],
                          @decoded["cloud_layer3_altitude_m"],
                          @decoded["cloud_layer3_altitude_ft"])
      else
        sky_str += sprintf(@strings['sky_str_format3'],
                          @decoded["cloud_layer2_condition"],
                          @decoded["cloud_layer2_altitude_m"],
                          @decoded["cloud_layer2_altitude_ft"])
      end
    end
    sky_str += "."

    if(@decoded.has_key?("visibility_miles"))
      visibility = sprintf(@strings['visibility_format'],
                          @decoded["visibility_km"],
                          @decoded["visibility_miles"])
    else
      visibility = ""
    end

    if (@decoded.has_key?("wind_meters_per_second") && @decoded["wind_meters_per_second"].to_i > 0)
      wind_str = sprintf(@strings['wind_str_format1'],
                        @decoded["wind_meters_per_second"],
                        @decoded["wind_miles_per_hour"])
      if (@decoded.has_key?("wind_gust_meters_per_second") && @decoded["wind_gust_meters_per_second"].to_i > 0)
        wind_str += sprintf(@strings['wind_str_format2'],
                            @decoded["wind_gust_meters_per_second"],
                            @decoded["wind_gust_miles_per_hour"])
      end
      wind_str += sprintf(@strings['wind_str_format3'],
                          @decoded["wind_dir_text"])
    else
      wind_str = @strings['wind_str_calm']
    end

    prec_str = ""
    if (@decoded.has_key?("precip_in"))
      prec_str += pretty_print_precip(@decoded["precip_mm"], @decoded["precip_in"]) + @strings['precip_last_hour']
    end
    if (@decoded.has_key?("precip_6h_in"))
      prec_str += pretty_print_precip(@decoded["precip_6h_mm"], @decoded["precip_6h_in"]) + @strings['precip_last_6_hours']
    end
    if (@decoded.has_key?("precip_24h_in"))
      prec_str += pretty_print_precip(@decoded["precip_24h_mm"], @decoded["precip_24h_in"]) + @strings['precip_last_24_hours']
    end
    if (@decoded.has_key?("snow_in"))
      prec_str += sprintf(@strings['precip_snow'], @decoded["snow_mm"], @decoded["snow_in"])
    end

    temp_str = ""
    if (@decoded.has_key?("temp_max6h_c") && @decoded.has_key?("temp_min6h_c"))
      temp_str += sprintf(@strings['temp_min_max_6_hours'],
                          @decoded["temp_max6h_c"],
                          @decoded["temp_min6h_c"],
                          @decoded["temp_max6h_f"],
                          @decoded["temp_min6h_f"])
    else
      if (@decoded.has_key?("temp_max6h_c"))
        temp_str += sprintf(@strings['temp_max_6_hours'],
                            @decoded["temp_max6h_c"],
                            @decoded["temp_max6h_f"])
      end
      if (@decoded.has_key?("temp_min6h_c"))
        temp_str += sprintf(@strings['temp_max_6_hours'],
                            @decoded["temp_min6h_c"],
                            @decoded["temp_min6h_f"])
      end
    end
    if (@decoded.has_key?("temp_max24h_c"))
      temp_str += sprintf(@strings['temp_min_max_24_hours'],
                          @decoded["temp_max24h_c"],
                          @decoded["temp_min24h_c"],
                          @decoded["temp_max24h_f"],
                          @decoded["temp_min24h_f"])
    end

    if (@decoded.has_key?("weather"))
      weather_str = sprintf(@strings['current_weather'], @decoded["weather"])
    else
      weather_str = ''
    end

    return sprintf(@strings['pretty_print_metar'],
                  weather_age,
                  @date,
                  wind_str, @decoded["station"], @decoded["temp_c"],
                  @decoded["temp_f"], @decoded["altimeter_hpa"],
                  @decoded["altimeter_inhg"],
                  @decoded["rel_humidity"], sky_str,
                  visibility, weather_str, prec_str, temp_str).strip
  end

  def to_s
    @input
  end
end


class WeatherPlugin < Plugin
  
  def help(plugin, topic="")
    "weather <ICAO> => display the current weather at the location specified by the ICAO code [Lookup your ICAO code at http://www.nws.noaa.gov/tg/siteloc.shtml - this will also store the ICAO against your nick, so you can later just say \"weather\", weather => display the current weather at the location you last asked for"
  end

  def get_metar(station)
    station.upcase!
    
    result = @bot.httputil.get(URI.parse("http://weather.noaa.gov/pub/data/observations/metar/stations/#{station}.TXT"))
    return nil unless result
    return Metar.new(result)
  end

  
  def initialize
    super
    # this plugin only wants to store strings
    class << @registry
      def store(val)
        val
      end
      def restore(val)
        val
      end
    end
    @metar_cache = Hash.new
  end
  
  def describe(m, where)
    if @metar_cache.has_key?(where) &&
       Time.now - @metar_cache[where].date < 3600
      met = @metar_cache[where]
    else
      met = get_metar(where)
    end
    
    if met
      m.reply met.pretty_print
      @metar_cache[where] = met
    else
      m.reply "couldn't find weather data for #{where}"
    end
  end

  def weather(m, params)
    if params[:where]
      @registry[m.sourcenick] = params[:where]
      describe(m,params[:where])
    else
      if @registry.has_key?(m.sourcenick)
        where = @registry[m.sourcenick]
        describe(m,where)
      else
        m.reply "I don't know where you are yet! Lookup your code at http://www.nws.noaa.gov/tg/siteloc.shtml and tell me 'weather <code>', then I'll know."
      end
    end
  end
end
plugin = WeatherPlugin.new
plugin.map 'weather :where', :defaults => {:where => false}
