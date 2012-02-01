class MathPlugin < Plugin
  @@digits = {
     "first" => "1",
     "second" => "2",
     "third" => "3",
     "fourth" => "4",
     "fifth" => "5",
     "sixth" => "6",
     "seventh" => "7",
     "eighth" => "8",
     "ninth" => "9",
     "tenth" => "10",
     "one" => "1",
     "two" => "2",
     "three" => "3",
     "four" => "4",
     "five" => "5",
     "six" => "6",
     "seven" => "7",
     "eight" => "8",
     "nine" => "9",
     "ten" => "10"
  };

  def name
    "math"
  end
  def help(plugin, topic="")
    "math <expression>, evaluate mathematical expression"
  end
  def privmsg(m)
    unless(m.params)
      m.reply "incorrect usage: " + help(m.plugin)
      return
    end

    expr = m.params.dup
    @@digits.each {|k,v|
      expr.gsub!(/\b#{k}\b/, v)
    }

    # ruby doesn't like floating-point values without a 0
    # in front of them, so find any non-digit followed by
    # a .<digits> and insert a 0 before the .
    expr.gsub!(/(\D|^)(\.\d+)/,'\10\2')

    while expr =~ /(exp ([\w\d]+))/
      exp = $1
      val = Math.exp($2).to_s
      expr.gsub!(/#{Regexp.escape exp}/, "+#{val}")
    end

    while expr =~ /^\s*(dec2hex\s*(\d+))\s*\?*/
      exp = $1
      val = sprintf("%x", $2)
      expr.gsub!(/#{Regexp.escape exp}/, "+#{val}")
    end

    expr.gsub(/\be\b/, Math.exp(1).to_s)

    while expr =~ /(log\s*((\d+\.?\d*)|\d*\.?\d+))\s*/
      exp = $1
      res = $2

      if res == 0
        val = "Infinity"
      else
        val = Math.log(res).to_s
      end

      expr.gsub!(/#{Regexp.escape exp}/, "+#{val}")
    end

    while expr =~ /(bin2dec ([01]+))/
      exp = $1
      val = join('', unpack('B*', pack('N', $2)))
      val.gsub!(/^0+/, "")
      expr.gsub!(/#{Regexp.escape exp}/, "+#{val}")
    end

    expr.gsub!(/ to the power of /, " ** ")
    expr.gsub!(/ to the /, " ** ")
    expr.gsub!(/\btimes\b/, "*")
    expr.gsub!(/\bdiv(ided by)? /, "/ ")
    expr.gsub!(/\bover /, "/ ")
    expr.gsub!(/\bsquared/, "**2 ")
    expr.gsub!(/\bcubed/, "**3 ")
    expr.gsub!(/\bto\s+(\d+)(r?st|nd|rd|th)?( power)?/, '**\1 ')
    expr.gsub!(/\bpercent of/, "*0.01*")
    expr.gsub!(/\bpercent/, "*0.01")
    expr.gsub!(/\% of\b/, "*0.01*")
    expr.gsub!(/\%/, "*0.01")
    expr.gsub!(/\bsquare root of (\d+(\.\d+)?)/, '\1 ** 0.5 ')
    expr.gsub!(/\bcubed? root of (\d+(\.\d+)?)/, '\1 **(1.0/3.0) ')
    expr.gsub!(/ of /, " * ")
    expr.gsub!(/(bit(-| )?)?xor(\'?e?d( with))?/, "^")
    expr.gsub!(/(bit(-| )?)?or(\'?e?d( with))?/, "|")
    expr.gsub!(/bit(-| )?and(\'?e?d( with))?/, "& ")
    expr.gsub!(/(plus|and)/, "+")

    debug expr
    if (expr =~ /^\s*[-\d*+\s()\/^\.\|\&\*\!]+\s*$/ &&
       expr !~ /^\s*\(?\d+\.?\d*\)?\s*$/ &&
       expr !~ /^\s*$/ &&
       expr !~ /^\s*[( )]+\s*$/)

       begin
         debug "evaluating expression \"#{expr}\""
         answer = eval(expr)
         if answer =~ /^[-+\de\.]+$/
           answer = sprintf("%1.12f", answer)
           answer.gsub!(/\.?0+$/, "")
           answer.gsub!(/(\.\d+)000\d+/, '\1')
           if (answer.length > 30)
             answer = "a number with >30 digits..."
           end
         end
         m.reply answer.to_s
       rescue Exception => e
         error e
         m.reply "illegal expression \"#{m.params}\""
         return
       end
    else
      m.reply "illegal expression \"#{m.params}\""
      return
    end
  end
end
plugin = MathPlugin.new
plugin.register("math")
plugin.register("maths")
