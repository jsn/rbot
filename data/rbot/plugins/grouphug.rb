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

  def get_confessions(html)
    return [] unless html
    start = html.index(START)
    res = html[start, html.length - start].scan(REG)
    return [] unless res
    return res.map { |quote|
      quote[0].ircify_html
    }
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
        confessions = get_confessions(data)
        if confessions.length > 1
          warn "more than one confession found!"
          warn confessions
        end
        confessions << "no confession ##{params[:num]} found" if confessions.empty?
        m.reply confessions.first
      else # Cache random confessions
        if @confessions.empty?
          data = @bot.httputil.get("http://grouphug.us/#{path}", opts)
          @confessions.replace get_confessions(data)
        end
        @confessions << "no confessions found!" if @confessions.empty?
        m.reply @confessions.pop
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

