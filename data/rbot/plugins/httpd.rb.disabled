require 'webrick'

class HttpPlugin < Plugin
  include WEBrick


  def initialize
    super
    @http_server = HTTPServer.new(
      :Port => 5555
    )
    @http_server.mount_proc("/") { |req, resp|
      resp['content-type'] = 'text/html'
      resp.body = "<html><head><title>rbot httpd plugin</title></head><body>"
      resp.body += "#{@bot.status} <br />"
      resp.body += "hello from rbot."
      resp.body += "</body>"
      raise HTTPStatus::OK
    }
    Thread.new {
      @http_server.start
    }
  end
  def cleanup
    @http_server.shutdown
    super
  end
  def help(plugin, topic="")
    "no help yet"
  end
  def privmsg(m)
  end
end

plugin = HttpPlugin.new
plugin.register("http")
