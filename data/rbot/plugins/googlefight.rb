#-- vim:sw=2:et
#++
#
# :title: Googlefight plugin for rbot
#
# Author:: Raine Virta <rane@kapsi.fi
# Copyright:: (C) 2009 Raine Virta
# License:: GPL v2

class GoogleFightPlugin < Plugin
  def help(plugin, topic)
    "googlefight <keyword 1> <keyword 2> [... <keyword n+1>] => battles given keywords based on amount of google search results and announces the winner!"
  end

  def fight(m, params)
    keywords = parse_keywords(params)
    return if keywords.nil?

    keywords.map! do |k|
      [k, google_count(k)]
    end

    m.reply output(keywords)
  end

  def output(result)
    result = result.sort_by { |e| e[1] }.reverse
    str = result.map do |kw|
      "%{keyword} (%{count})" % {
        :keyword => Bold+kw[0]+Bold,
        :count   => kw[1].to_s.gsub(/(\d)(?=(\d\d\d)+(?!\d))/, "\\1,")
      }
    end.join(" vs. ")

    unless result[0][1].zero?
      str << _(" -- %{keyword} wins!") % {
        :keyword => Bold+result[0][0]+Bold
      }
    else
      str << _(" -- no winner here!")
    end
  end

  def parse_keywords(params)
    str = params[:keywords].join(" ")

    # foo "foo bar" bar
    # no separators so assume they're all separate keywords
    if str.match(/(?:"[\w\s]+"|\w+)(?: (?:"[\w\s]+"|\w+))+/)
      str.scan(/"[^"]+"|\S+/).flatten
    end
  end

  def google_count(query)
    url  = 'http://www.google.com/search?hl=en&safe=off&btnG=Search&q=' << CGI.escape(query)
    html = Net::HTTP.get(URI.parse((url)))
    res  = html.scan(%r{About ([\d,]+) results})
    res[0][0].to_s.tr(",", "").to_i
  end
end

plugin = GoogleFightPlugin.new
plugin.map "googlefight *keywords", :action => "fight",
  :requirements => { :keywords => /^[\w\s"]+? (?:(?:(?:\||vs\.) )?[\w\s"]+?)+/ }
