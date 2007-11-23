#-- vim:sw=2:et
#++
#
# :title: Twitter Status Update for rbot
#
# Author:: Carter Parks (carterparks) <carter@carterparks.com>
# Author:: Giuseppe "Oblomov" Bilotta <giuseppe.bilotta@gmail.com>
#
# Copyright:: (C) 2007 Carter Parks
# Copyright:: (C) 2007 Giuseppe Bilotta
#
# Users can setup their twitter username and password and then begin updating
# twitter whenever

require 'rexml/rexml'
require 'cgi'

class TwitterPlugin < Plugin
  Config.register Config::IntegerValue.new('twitter.status_count',
    :default => 1, :validate => Proc.new { |v| v > 0 && v <= 10},
    :desc => "Maximum number of status updates shown by 'twitter status'")
  Config.register Config::IntegerValue.new('twitter.friends_status_count',
    :default => 3, :validate => Proc.new { |v| v > 0 && v <= 10},
    :desc => "Maximum number of status updates shown by 'twitter friends status'")

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

    @header = {
      'X-Twitter-Client' => 'rbot twitter plugin'
    }
  end

  # return a help string when the bot is asked for help on this plugin
  def help(plugin, topic="")
    return "twitter status [nick] => show nick's (or your) status, use 'twitter friends status [nick]' to also show the friends' timeline | twitter update [status] => updates your status on twitter | twitter identify [username] [password] => ties your nick to your twitter username and password"
  end

  # update the status on twitter
  def get_status(m, params)

    nick = params[:nick] || @registry[m.sourcenick + "_username"]

    if not nick
      m.reply "you should specify the username of the twitter touse, or identify using 'twitter identify [username] [password]'"
      return false
    end

    user = URI.escape(nick)

    count = @bot.config['twitter.status_count']
    unless params[:friends]
      uri = "http://twitter.com/statuses/user_timeline/#{user}.xml?count=#{count}"
    else
      count = @bot.config['twitter.friends_status_count']
      uri = "http://twitter.com/statuses/friends_timeline/#{user}.xml"
    end

    response = @bot.httputil.get(uri, :headers => @header, :cache => false)
    debug response

    texts = []

    if response
      begin
        rex = REXML::Document.new(response)
        rex.root.elements.each("status") { |st|
          # month, day, hour, min, sec, year = st.elements['created_at'].text.match(/\w+ (\w+) (\d+) (\d+):(\d+):(\d+) \S+ (\d+)/)[1..6]
          # debug [year, month, day, hour, min, sec].inspect
          # time = Time.local(year.to_i, month, day.to_i, hour.to_i, min.to_i, sec.to_i)
          time = Time.parse(st.elements['created_at'].text)
          now = Time.now
          # Sometimes, time can be in the future; invert the relation in this case
          delta = ((time > now) ? time - now : now - time)
          msg = st.elements['text'].to_s + " (#{Utils.secs_to_string(delta.to_i)} ago via #{st.elements['source'].to_s})"
          author = ""
          if params[:friends]
            author = Utils.decode_html_entities(st.elements['user'].elements['name'].text) + ": " rescue ""
          end
          texts << author+Utils.decode_html_entities(msg).ircify_html
        }
        if params[:friends]
          # friends always return the latest 20 updates, so we clip the count
          texts[count..-1]=nil
        end
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

    user = URI.escape(@registry[m.sourcenick + "_username"])
    pass = URI.escape(@registry[m.sourcenick + "_password"])
    uri = "http://#{user}:#{pass}@twitter.com/statuses/update.xml"

    msg = params[:status].to_s

    if msg.length > 160
      m.reply "your status message update is too long, please keep it under 140 characters if possible, 160 characters maximum"
      return
    end

    if msg.length > 140
      m.reply "your status message is longer than 140 characters, which is not optimal, but I'm going to update anyway"
    end

    source = "source=rbot"
    msg = "status=#{CGI.escape(msg)}"
    body = [source,msg].join("&")

    response = @bot.httputil.post(uri, body, :headers => @header)
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
plugin.map 'twitter :friends [status] [:nick]', :action => "get_status", :requirements => { :friends => /^friends?$/ }, :threaded => true

