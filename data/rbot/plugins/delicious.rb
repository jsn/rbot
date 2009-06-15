#-- vim:sw=2:et
#++
#
# :title: Del.icio.us plugin
#
# Author:: dmitry kim <dmitry.kim@gmail.com>
# Copyright:: (C) 2007 dmitry kim
# License:: MIT
#
# This plugin uses url_added hook (event) to submit all urls seen by url.rb
# plugin to a preconfigured account on http://del.icio.us/
#
require 'rexml/document'
require 'cgi'

class DeliciousPlugin < Plugin
  DIU_BASE = 'https://api.del.icio.us/v1/posts/'

  attr_accessor :last_error

  Config.register Config::StringValue.new('delicious.user',
    :default => '', :desc => "Username on del.icio.us")
  Config.register Config::StringValue.new('delicious.password',
    :default => '', :desc => "Password on del.icio.us")
  Config.register Config::StringValue.new('delicious.user_fmt',
    :default => 'user:%s', :desc => "How to convert users to tags?")
  Config.register Config::StringValue.new('delicious.channel_fmt',
    :default => 'channel:%s', :desc => "How to convert channels to tags?")

  def help(plugin, topic="")
    "logs urls seen to del.icio.us. you can use [tags: tag1 tag2 ...] to provide tags. special tags are: #{Underline}!hide#{Underline} - log the url as non-shared, #{Underline}!skip#{Underline} - don't log the url. Commands: !#{Bold}delicious#{Bold} => show url of del.icio.us feed of bot url log. "
  end

  def diu_req(verb, opts = {})
    uri = URI.parse(DIU_BASE + verb)
    uri.query = opts.map { |k, v| "#{k}=#{CGI.escape v}" }.join('&')
    uri.user = @bot.config['delicious.user']
    uri.password = @bot.config['delicious.password']

    if uri.user.empty? || uri.password.empty?
      self.last_error = 'delicious.user and delicious.password must be set!'
      raise self.last_error
    end

    return REXML::Document.new(@bot.httputil.get(uri, :cache => false))
  end

  def diu_add(url, opts = {})
    old = diu_req('get', :url => url).root.get_elements('/posts/post')[0] rescue nil
    opts[:tags] ||= ''
    if old
      opts[:description] ||= old.attribute('description').to_s
      opts[:extended] ||= old.attribute('extended').to_s
      opts[:tags] = [opts[:tags].split, old.attribute('tag').to_s.split].flatten.uniq.compact.join(' ')
      debug "reusing existing del.icio.us post"
    else
      debug "adding new del.icio.us post"
    end
    opts[:url] = url
    diu_req('add', opts)
  end

  def event_url_added(url, options = {})
    debug("called with #{url}, #{options.inspect}")
    if @bot.config['delicious.user'].empty?
      debug "del.icio.us plugin not configured, skipping"
      return
    end
    opts = Hash.new
    opts[:description] = options[:title] || options[:info] || url
    opts[:extended] = options[:extra] if options[:extra]
    opts[:tags] = @bot.config['delicious.user_fmt'] % options[:nick]
    if options[:channel]
      opts[:tags] << ' ' + (@bot.config['delicious.channel_fmt'] % options[:channel])
    end
    if options[:ircline] and options[:ircline].match(/\[tag(?:s)?:([^\]]+)\]/)
      tags = $1
      tags.tr(',', ' ').split(/\s+/).each do |t|
        if t.sub!(/^!/, '')
          case t
          when 'nolog', 'no-log', 'dont-log', 'dontlog', 'skip'
            debug "skipping #{url} on user request"
            return
          when 'private', 'unshared', 'not-shared', 'notshared', 'hide'
            debug "hiding #{url} on user request"
            opts[:shared] = 'no'
          end
        else
          opts[:tags] << ' ' + t
        end
      end
    end
    debug "backgrounding del.icio.us api call"
    Thread.new { diu_add(url, opts) }
  end

  def delicious(m, params)
    uname = @bot.config['delicious.user']
    repl = String.new
    if uname.empty?
      repl << 'error: del.icio.us username not set'
    else
      repl << "http://del.icio.us/#{uname}"
      if self.last_error
        repl << ", last error: #{self.last_error}"
        self.last_error = nil
      end
    end
    m.reply repl
  end
end
plugin = DeliciousPlugin.new
plugin.map 'delicious'
