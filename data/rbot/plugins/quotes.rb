#-- vim:sw=2:et
#++
#
# :title: Quotes plugin
#
# TODO:: use message mapper instead of multiple ifs
# TODO:: switch to db

define_structure :Quote, :num, :date, :source, :quote

class QuotePlugin < Plugin
  def initialize
    super
    @lists = Hash.new
    @changed = Hash.new
    Dir["#{@bot.botclass}/quotes/*"].each {|f|
      next if File.directory?(f)
      channel = File.basename(f)
      @lists[channel] = Array.new if(!@lists.has_key?(channel))
      IO.foreach(f) {|line|
        if(line =~ /^(\d+) \| ([^|]+) \| (\S+) \| (.*)$/)
          num = $1.to_i
          @lists[channel][num] = Quote.new(num, $2, $3, $4)
        end
      }
      @changed[channel] = false
    }
  end

  def save
    Dir.mkdir("#{@bot.botclass}/quotes") if(!FileTest.directory?("#{@bot.botclass}/quotes"))
    @lists.each {|channel, quotes|
      begin
        if @changed[channel]
          debug "Writing new quotefile for channel #{channel} ..."
          Utils.safe_save("#{@bot.botclass}/quotes/#{channel}") {|file|
            quotes.compact.each {|q| 
              file.puts "#{q.num} | #{q.date} | #{q.source} | #{q.quote}"
            }
          }
          @changed[channel] = false
        else
          debug "Not writing quotefile for channel #{channel} (unchanged)"
        end
      rescue => e
        error "failed to write quotefile for channel #{channel}!\n#{$!}"
        error "#{e.class}: #{e}"
        error e.backtrace.join("\n")
      end
    }
  end

  def cleanup
    @lists.clear
    @changed.clear
    super
  end

  def addquote(source, channel, quote)
    @lists[channel] = Array.new if(!@lists.has_key?(channel))
    num = @lists[channel].length 
    @lists[channel][num] = Quote.new(num, Time.new, source.fullform, quote)
    @changed[channel] = true
    return num
  end

  def getquote(source, channel, num=nil)
    return nil unless(@lists.has_key?(channel))
    return nil unless(@lists[channel].length > 0)
    if(num)
      if(@lists[channel][num])
        return @lists[channel][num], @lists[channel].length - 1
      end
    else
      # random quote
      return @lists[channel].compact[rand(@lists[channel].nitems)],
      @lists[channel].length - 1
    end
  end

  def delquote(channel, num)
    return false unless(@lists.has_key?(channel))
    return false unless(@lists[channel].length > 0)
    if(@lists[channel][num])
      @lists[channel][num] = nil
      @lists[channel].pop if num == @lists[channel].length - 1
      @changed[channel] = true
      return true
    end
    return false
  end

  def countquote(source, channel=nil, regexp=nil)
    unless(channel)
      total=0
      @lists.each_value {|l|
        total += l.compact.length
      }
      return total
    end
    return 0 unless(@lists.has_key?(channel))
    return 0 unless(@lists[channel].length > 0)
    if(regexp)
      matches = @lists[channel].compact.find_all {|a| a.quote =~ /#{regexp}/i }
    else
      matches = @lists[channel].compact
    end
    return matches.length
  end

  def searchquote(source, channel, regexp)
    return nil unless(@lists.has_key?(channel))
    return nil unless(@lists[channel].length > 0)
    matches = @lists[channel].compact.find_all {|a| a.quote =~ /#{regexp}/i }
    if(matches.length > 0)
      return matches[rand(matches.length)], @lists[channel].length - 1
    else
      return nil
    end
  end

  def help(plugin, topic="")
    case plugin
    when "addquote"
      _("addquote [<channel>] <quote> => Add quote <quote> for channel <channel>. You only need to supply <channel> if you are addressing %{nick} privately.") % { :nick => @bot.nick }
    when "delquote"
      _("delquote [<channel>] <num> => delete quote from <channel> with number <num>. You only need to supply <channel> if you are addressing %{nick} privately.") % { :nick => @bot.nick }
    when "getquote"
      _("getquote [<channel>] [<num>] => get quote from <channel> with number <num>. You only need to supply <channel> if you are addressing %{nick} privately. Without <num>, a random quote will be returned.") % { :nick => @bot.nick }
    when "searchquote"
      _("searchquote [<channel>] <regexp> => search for quote from <channel> that matches <regexp>. You only need to supply <channel> if you are addressing %{nick} privately.") % { :nick => @bot.nick }
    when "topicquote"
      _("topicquote [<channel>] [<num>] => set topic to quote from <channel> with number <num>. You only need to supply <channel> if you are addressing %{nick} privately. Without <num>, a random quote will be set.") % { :nick => @bot.nick }
    when "countquote"
      _("countquote [<channel>] <regexp> => count quotes from <channel> that match <regexp>. You only need to supply <channel> if you are addressing %{nick} privately.") % { :nick => @bot.nick }
    when "whoquote"
      _("whoquote [<channel>] <num> => show who added quote <num>. You only need to supply <channel> if you are addressing %{nick} privately") % { :nick => @bot.nick }
    when "whenquote"
      _("whenquote [<channel>] <num> => show when quote <num> was added. You only need to supply <channel> if you are addressing %{nick} privately") % { :nick => @bot.nick }
    else
      _("Quote module (Quote storage and retrieval) topics: addquote, delquote, getquote, searchquote, topicquote, countquote, whoquote, whenquote") % { :nick => @bot.nick }
    end
  end

  def cmd_addquote(m, p)
    channel = p[:channel] || m.channel.to_s
    quote = p[:quote].to_s
    num = addquote(m.source, channel, quote)
    m.reply _("added the quote (#%{num})") % { :num => num }
  end

  def cmd_delquote(m, p)
    channel = p[:channel] || m.channel.to_s
    num = p[:num].to_i
    if delquote(channel, num)
      m.okay
    else
      m.reply _("quote not found!")
    end
  end

  def cmd_getquote(m, p)
    channel = p[:channel] || m.channel.to_s
    num = p[:num] ? p[:num].to_i : nil
    quote, total = getquote(m.source, channel, num)
    if quote
      m.reply _("[%{num}] %{quote}") % {
        :num => quote.num,
        :quote => quote.quote
      }
    else
      m.reply _("quote not found!")
    end
  end

  def cmd_whoquote(m, p)
    channel = p[:channel] || m.channel.to_s
    num = p[:num] ? p[:num].to_i : nil
    quote, total = getquote(m.source, channel, num)
    if quote
      m.reply _("quote %{num} added by %{source}") % {
        :num => quote.num,
        :source => quote.source
      }
    else
      m.reply _("quote not found!")
    end
  end

  def cmd_whenquote(m, p)
    channel = p[:channel] || m.channel.to_s
    num = p[:num] ? p[:num].to_i : nil
    quote, total = getquote(m.source, channel, num)
    if quote
      m.reply _("quote %{num} added on %{date}") % {
        :num => quote.num,
        :date => quote.date
      }
    else
      m.reply _("quote not found!")
    end
  end

  def cmd_searchquote(m, p)
    channel = p[:channel] || m.channel.to_s
    reg = p[:reg].to_s
    quote, total = searchquote(m.source, channel, reg)
    if quote
      m.reply _("[%{num}] %{quote}") % {
        :num => quote.num,
        :quote => quote.quote
      }
    else
      m.reply _("quote not found!")
    end
  end

  def cmd_countquote(m, p)
    channel = p[:channel] || m.channel.to_s
    reg = p[:reg] ? p[:reg].to_s : nil
    total = countquote(m.source, channel, reg)
    if reg.length > 0
      m.reply _("%{total} quotes matching %{reg}") % {
        :total => total,
        :reg => reg
      }
    else
      m.reply _("%{total} quotes") % { :total => total }
    end
  end

  def cmd_topicquote(m, p)
    channel = p[:channel] || m.channel.to_s
    num = p[:num] ? p[:num].to_i : nil
    quote, total = getquote(m.source, channel, num)
    if quote
      @bot.topic channel, _("[%{num}] %{quote}") % {
        :num => quote.num,
        :quote => quote.quote
      }
    else
      m.reply _("quote not found!")
    end
  end
end

plugin = QuotePlugin.new
plugin.register("quotes")

plugin.default_auth('edit', false) # Prevent random people from removing quotes
plugin.default_auth('edit::add', true) # But allow them to add them

plugin.map "addquote *quote", :action => :cmd_addquote, :private => false, :auth_path => '!quote::edit::add!'
plugin.map "delquote :num", :action => :cmd_delquote, :private => false, :requirements => { :num => /^\d+$/ }, :auth_path => '!quote::edit::del!'
plugin.map "getquote [:num]", :action => :cmd_getquote, :private => false, :requirements => { :num => /^\d+$/ }, :auth_path => '!quote::view::get!'
plugin.map "whoquote :num", :action => :cmd_whoquote, :private => false, :requirements => { :num => /^\d+$/ }, :auth_path => '!quote::view::who!'
plugin.map "whenquote :num", :action => :cmd_whenquote, :private => false, :requirements => { :num => /^\d+$/ }, :auth_path => '!quote::view::when!'
plugin.map "searchquote *reg", :action => :cmd_searchquote, :private => false, :auth_path => '!quote::view::search!'
plugin.map "countquote [*reg]", :action => :cmd_countquote, :private => false, :auth_path => '!quote::view::count!'
plugin.map "topicquote [:num]", :action => :cmd_topicquote, :private => false, :requirements => { :num => /^\d+$/ }, :auth_path => '!quote::topic!'

plugin.default_auth('other::edit', false) # Prevent random people from editing other channels quote lists by default
plugin.default_auth('other::view', true) # But allow them to view them

plugin.map "addquote :channel *quote", :action => :cmd_addquote, :requirements => { :channel => Regexp::Irc::GEN_CHAN }, :auth_path => '!quote::other::edit::add!'
plugin.map "delquote :channel :num", :action => :cmd_delquote, :requirements => { :channel => Regexp::Irc::GEN_CHAN, :num => /^\d+$/ }, :auth_path => '!quote::other::edit::del!'
plugin.map "getquote :channel [:num]", :action => :cmd_getquote, :requirements => { :channel => Regexp::Irc::GEN_CHAN, :num => /^\d+$/ }, :auth_path => '!quote::other::view::get!'
plugin.map "whoquote :channel :num", :action => :cmd_whoquote, :requirements => { :channel => Regexp::Irc::GEN_CHAN, :num => /^\d+$/ }, :auth_path => '!quote::other::view::who!'
plugin.map "whenquote :channel :num", :action => :cmd_whenquote, :requirements => { :channel => Regexp::Irc::GEN_CHAN, :num => /^\d+$/ }, :auth_path => '!quote::other::view::when!'
plugin.map "searchquote :channel *reg", :action => :cmd_searchquote, :requirements => { :channel => Regexp::Irc::GEN_CHAN }, :auth_path => '!quote::other::view::search!'
plugin.map "countquote [:channel] [*reg]", :action => :cmd_countquote, :requirements => { :channel => Regexp::Irc::GEN_CHAN }, :auth_path => '!quote::other::view::count!'
plugin.map "topicquote :channel [:num]", :action => :cmd_topicquote, :requirements => { :channel => Regexp::Irc::GEN_CHAN, :num => /^\d+$/ }, :auth_path => '!quote::other::topic!'
