require 'rexml/document'
require 'uri/common'

class ChuckNorrisPlugin < Plugin
  include REXML

  def help(plugin, topic="")
    "chucknorris [<howmany>=1] => show a random chuck norris quote, or specify <howmany> quotes you want (maximum is 6)."
  end
  
  def chucknorris(m, params)
    howmany = params[:howmany].to_i
    howmany = 6 if howmany > 6

    factdata = @bot.httputil.get(URI.parse('http://www.4q.cc/chuck/rss.php'))
    unless factdata
      m.reply "Chuck Norris' facts roundhouse kicked the internet connection and totally wasted it."
      return
    end

    begin
      doc = Document.new factdata
      doc.get_elements('rss/channel/item')[1..howmany].each do |fact|
        m.reply fact.elements['description'].text
      end

    rescue ParseException => e
      puts "Error parsing chuck norris quote: #{e.inspect}"
      m.reply "Chuck Norris' facts were so intense that they blew up my XML parser."

    end

  end

end

plugin = ChuckNorrisPlugin.new
plugin.map 'chucknorris :howmany', :defaults => {:howmany => 1},
                                   :requirements => {:howmany => /^-?\d+$/} 
