#-- vim:sw=2:et
#++
#
# :title: Twitter Status Update for rbot
#
# Author:: Carter Parks (carterparks) <carter@carterparks.com>
# Author:: Giuseppe "Oblomov" Bilotta <giuseppe.bilotta@gmail.com>
#
# Copyright:: (C) 2007 Carter Parks
#
# Users can setup their twitter username and password and then begin updating
# twitter whenever

require 'rexml/rexml'

class TwitterPlugin < Plugin
  def initialize
    super
    
    class << @registry
      def store(val)
        val
      end
      def restore(val)
        val
      end
    end
  end
  
  # return a help string when the bot is asked for help on this plugin
  def help(plugin, topic="")
    return "twitter status [status] => updates your status on twitter | twitter identify [username] [password] => ties your nick to your twitter username and password"
  end
  
  # update the status on twitter
  def get_status(m, params)
  
    nick = params[:nick] || @registry[m.sourcenick + "_username"]

    if not nick
      m.reply "you should specify the username of the twitter touse, or identify using 'twitter identify [username] [password]'"
      return false
    end
      
    # TODO configurable count
    uri = "http://twitter.com/statuses/user_timeline/#{URI.escape(nick)}.xml?count=3"
    
    response = @bot.httputil.get(uri)
    debug response

    texts = []
    
    if response
      begin
        rex = REXML::Document.new(response)
        rex.root.elements.each("status") { |st|
          msg = st.elements['text'].to_s + " (#{st.elements['created_at'].to_s} via #{st.elements['source'].to_s})"
          texts << Utils.decode_html_entities(msg).ircify_html
        }
      rescue
        error $!
        m.reply "could not parse status for #{nick}"
        return false
      end
      m.reply texts.reverse.join("\n")
      return true
    else
      m.reply "could not get status for #{nick}"
      return false
    end
  end
  
  # update the status on twitter
  def update_status(m, params)
  

    unless @registry.has_key?(m.sourcenick + "_password") && @registry.has_key?(m.sourcenick + "_username")
      m.reply "you must identify using 'twitter identify [username] [password]'"
      return false
    end
      
    uri = "http://#{URI.escape(@registry[m.sourcenick + "_username"])}:#{URI.escape(@registry[m.sourcenick + "_password"])}@twitter.com/statuses/update.xml"
    
    response = @bot.httputil.post(uri, "status=#{URI.escape(params[:status].to_s)}")
    debug response
    
    if response.class == Net::HTTPOK
      m.reply "status updated"
    else
      m.reply "could not update status"
    end
  end
  
  # ties a nickname to a twitter username and password
  def identify(m, params)
    @registry[m.sourcenick + "_username"] = params[:username].to_s
    @registry[m.sourcenick + "_password"] = params[:password].to_s
    m.reply "you're all setup!"
  end
end

# create an instance of our plugin class and register for the "length" command
plugin = TwitterPlugin.new
plugin.map 'twitter identify :username :password', :action => "identify", :public => false
plugin.map 'twitter update *status', :action => "update_status", :threaded => true
plugin.map 'twitter status [:nick]', :action => "get_status", :threaded => true

