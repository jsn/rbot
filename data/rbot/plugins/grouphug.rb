#-- vim:sw=2:et
#++
#
# :title: Grouphug Plugin for rbot
#
# Author:: Mark Kretschmann <markey@web.de>
# Author:: Casey Link <unnamedrambler@gmail.com>
# Copyright:: (C) 2005 Mark Kretschmann
# Copyright:: (C) 2008 Casey Link
# License:: GPL v2

class GrouphugPlugin < Plugin
  START = '<div id="main"'
  REG  = Regexp.new('<div class="content">\s*<p>(.*?)</p>\s+</div>', Regexp::MULTILINE)
  REGPOST = Regexp.new('title>(.*?) \| Group Hug')
  def initialize
    super
    @confessions = Array.new
  end

  def help( plugin, topic="" )
    return _("Grouphug plugin. Confess! Usage: 'confess' for random confession, 'confess <number>' for specific one, 'confess <confession>' to share your own confession. Confessions must be at least 10 words.")
  end

  def post_confession(m, params)
    c = params[:confession]
    if c.length < 10
      diff = 10 - c.length
      m.reply _("Confession must be at least 10 words. You need %{m} more.") % {:m => diff}
      return
    end
    uri = "http://beta.grouphug.us/confess"
    form_id = "form_id=confession_node_form"
    op = "op=Submit"
    changed = "changed="
    body = "body=#{c}"
    msg = [form_id,body,changed,op].join("&")

    response = bot.httputil.post(uri, msg)
    debug response.body
    if response.class == Net::HTTPOK
      num = response.body.scan(REGPOST)
      m.reply _("Confession posted: http://beta.grouphug.us/confessions/%{n}") % {:n => num}
    else
      m.reply _("I couldn't share your confession.")
    end
  end


  def confess(m, params)
    opts = { :cache => false }
    path = "random"
    begin
      # Fetch a specific question - separate from cache
      if params[:num]
        path = "confessions/#{params[:num]}"
        opts.delete(:cache)
        data = @bot.httputil.get("http://grouphug.us/#{path}", opts)
        start = data.index(START)
        res = data[start, data.length - start].scan(REG)
        confession = res.first[0].ircify_html
        confession = "no confession ##{params[:num]} found" if confession.empty? and params[:num]
        m.reply confession
      else # Cache random confessions
        if @confessions.empty?
          data = @bot.httputil.get("http://grouphug.us/#{path}", opts)
          start = data.index(START)
          res = data[start, data.length - start].scan(REG)
          res.each do |quote|
            @confessions << quote[0].ircify_html
          end
        end
        confession = @confessions.pop
        m.reply confession
      end
    rescue Exception => e
      error e
      m.reply "failed to connect to grouphug.us"
    end
  end
end


plugin = GrouphugPlugin.new

plugin.default_auth('create', false)

plugin.map "grouphug [:num]",
  :thread => true, :action => :confess, :requirements => { :num => /\d+/ }
plugin.map "confess [:num]",
  :thread => true, :action => :confess, :requirements => { :num => /\d+/ }
plugin.map "confess *confession", :thread => true, :action => :post_confession, :auth_path => 'create'

