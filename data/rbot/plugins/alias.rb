#-- vim:sw=2:et
#++
#
# :title: Alias plugin for rbot
#
# Author:: Yaohan Chen <yaohan.chen@gmail.com>
# Copyright:: (C) 2007 Yaohan Chen
# License:: GPLv2
#
# This plugin allows defining aliases for rbot commands. Aliases are like normal rbot
# commands and can take parameters. When called, they will be substituted into an
# exisitng rbot command and that is run.
#
# == Example Session
#   < alias googlerbot *terms => google site:linuxbrit.co.uk/rbot/ <terms>
#   > okay
#   < googlerbot plugins
#   > Results for site:linuxbrit.co.uk/rbot/ plugins: ....
#
# == Security
# By default, only the owner can define and remove aliases, while everyone else can
# use and view them. When a command is executed with an alias, it's mapped normally with
# the alias user appearing to attempt to execute the command. Therefore it should be not
# possible to use aliases to circumvent permission sets. Care should be taken when
# defining aliases, due to these concerns:
# * Defined aliases can potentially override other plugins' maps, if this plugin is
#   loaded first
# * Aliases can cause infinite recursion of aliases and/or commands. The plugin attempts
#   to detect and stop this, but a few recursive calls can still cause spamming

require 'yaml'

class AliasPlugin < Plugin
  # an exception raised when loading or getting input of invalid alias definitions
  class AliasDefinitionError < ArgumentError
  end

  MAX_RECURSION_DEPTH = 10

  def initialize
    super
    @data_path = "#{@bot.botclass}/alias/"
    @data_file = "#{@data_path}/aliases.yaml"
    # hash of alias => command entries
    @aliases = if File.exist?(@data_file)
                 YAML.load_file(@data_file)
               else
                 Hash.new
               end
    @aliases.each_pair do |a, c|
      begin
        add_alias(a, c)
      rescue AliasDefinitionError
	warning _("Invalid alias entry %{alias} : %{command} in %{filename}: %{reason}") %
                {:alias => a, :command => c, :filename => @data_file, :reason => $1}
      end
    end 
  end 

  def save 
    Dir.mkdir(@data_path) unless File.exist?(@data_path)
    File.open(@data_file, 'w') {|f| f.write @aliases.to_yaml}
  end

  def cmd_add(m, params)
    begin
      add_alias(params[:text].to_s, params[:command].to_s)
      m.okay
    rescue AliasDefinitionError
      m.reply _('The definition you provided is invalid: %{reason}') % {:reason => $!}
    end
  end

  def cmd_remove(m, params)
    text = params[:text].to_s
    if @aliases.has_key?(text)
      @aliases.delete(text)
      # TODO when rbot supports it, remove the mapping corresponding to the alias
      m.okay
    else
      m.reply _('No such alias is defined')
    end
  end

  def cmd_list(m, params)
    if @aliases.empty?
      m.reply _('No aliases defined')
    else
      m.reply @aliases.map {|a, c| "#{a} => #{c}"}.join(' | ')
    end
  end

  def cmd_whatis(m, params)
    text = params[:text].to_s
    if @aliases.has_key?(text)
      m.reply _('Alias of %{command}') % {:command => @aliases[text]}
    else
      m.reply _('No such alias is defined')
    end
  end

  def add_alias(text, command)
    # each alias is implemented by adding a message map, whose handler creates a message
    # containing the aliased command

    command.grep(/<(\w+)>/) {$1}.all? {|s| text =~ /(?:^|\s)[:*]#{s}(?:\s|$)/ } or
      raise AliasDefinitionError.new(_('Not all substitutions in command text have matching arguments in alias text'))
    
    @aliases[text] = command
    map text, :action => :"alias_handle<#{text}>", :auth_path => 'run'
  end

  def respond_to?(name, include_private=false)
    name.to_s =~ /\Aalias_handle<.+>\Z/ || super
  end

  def method_missing(name, *args, &block)
    if name.to_s =~ /\Aalias_handle<(.+)>\Z/
      m, params = args
      # messages created by alias handler will have a depth method, which returns the 
      # depth of "recursion" caused by the message
      current_depth = if m.respond_to?(:depth) then m.depth else 0 end
      if current_depth > MAX_RECURSION_DEPTH
        m.reply _('The alias seems to have caused infinite recursion. Please examine your alias definitions')
        return
      end

      command = @aliases[$1]
      if command
        # create a fake message containing the intended command
        new_msg = PrivMessage.new(@bot, m.server, m.server.user(m.source), m.target,
                                    command.gsub(/<(\w+)>/) {|arg| params[:"#{$1}"].to_s})
        # tag incremented depth on the message
        class << new_msg
          self
        end.send(:define_method, :depth) {current_depth + 1}

        @bot.plugins.privmsg(new_msg)
      else
        m.reply _("Error handling the alias, the command is not defined")
      end
    else
      super(name, *args, &block)
    end
  end

  def help(plugin, topic='')
    case topic
    when ''
      _('Create and use aliases for commands. Topics: create, commands')
    when 'create'
      _('"alias <text> => <command>" => add text as an alias of command. Text can contain placeholders marked with : or * for :words and *multiword arguments. The command can contain placeholders enclosed with < > which will be substituded with argument values. For example: alias googlerbot *terms => google site:linuxbrit.co.uk/rbot/ <terms>')
    when 'commands'
      _('alias list => list defined aliases | alias whatis <alias> => show definition of the alias | alias remove <alias> => remove defined alias | see the "create" topic about adding aliases')
    end
  end
end

plugin = AliasPlugin.new
plugin.default_auth('edit', false)
plugin.default_auth('run', true)
plugin.default_auth('list', true)

plugin.map 'alias list',
           :action => :cmd_list,
           :auth_path => 'view'
plugin.map 'alias whatis *text',
           :action => :cmd_whatis,
           :auth_path => 'view'
plugin.map 'alias remove *text',
           :action => :cmd_remove,
           :auth_path => 'edit'
plugin.map 'alias *text => *command',
           :action => :cmd_add,
           :auth_path => 'edit'



