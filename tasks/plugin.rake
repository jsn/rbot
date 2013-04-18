task :plugin, :name  do |t, args|
  if args.to_a.empty?
    raise <<-eos
Usage:   rake #{t}[<plugin name>]
Example: rake plugin[Greet]
    eos
  end
  plugin_name = args.name.downcase
  class_name  = "#{plugin_name.capitalize}Plugin"
  plugin_template = <<-eot
class #{class_name} < Plugin
  def help(plugin, topic="")
    topics = %w{hello}

    case topic
    when 'hello'
      _("hello, this is an example topic of my new plugin! :)")
    else
      _("#{plugin_name} plugin - topics: %{list}") % {
        :list => topics.join(", ")
      }
    end
  end

  def example(m, params)
    m.reply "example action was triggered"
  end
end

plugin = #{class_name}.new
plugin.map "#{plugin_name} [:arg]", :action => 'example'
  eot

  plugins_path = File.expand_path(File.join(File.dirname(__FILE__), '..', 'data/rbot/plugins'))
  file_path    = File.join(plugins_path, "#{plugin_name}.rb")

  if File.exist?(file_path)
    puts "File exists: #{file_path}"
    print "Overwrite? "
    input = STDIN.gets.chomp
    puts

    exit unless input =~ /y(es)?/
  end

  File.open(file_path, "w") do |f|
    f << plugin_template
  end

  puts "Plugin skeleton for #{class_name} written to #{file_path}!"
  puts "Now issue `rescan` on the bot and use the command `help #{plugin_name}` to see that the plugin works."
  puts
end
