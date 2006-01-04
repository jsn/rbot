require "rubygems"
require "shorturl"

class RubyURL < Plugin

  # return a help string when the bot is asked for help on this plugin
  def help(plugin, topic="")
    return "rubyurl <your long url>"
  end

  # reply to a private message that we've registered for
  def privmsg(m)

    # m.params contains the rest of the message, m.plugin contains the first
    # word (useful because it's possible to register for multiple commands)
    unless(m.params)
      m.reply "incorrect usage. " + help(m.plugin)
    end

    # TODO: might want to add a check here to validate the url
    # if they call 'rubyurl help' backwards, don't return a lame link

    if (m.params == "help")
      m.reply "Try again. Correct usage is: " + help(m.plugin)
      return false
    end

    # call the ShortURL library with the value of the url
    url = ShortURL.shorten(m.params)


    m.reply "Your RubyURL: #{url}"

  end
end

# create an instance of the RubyURL class and register it as a plugin
rubyurl = RubyURL.new
rubyurl.register("rubyurl")
