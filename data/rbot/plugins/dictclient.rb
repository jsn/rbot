#-- vim:sw=2:et
#++
#
# :title: DICT (RFC 2229) Protocol Client Plugin for rbot
#
# Author:: Yaohan Chen <yaohan.chen@gmail.com>
# Copyright:: (C) 2007 Yaohan Chen
# License:: GPL v2
#
# Looks up words on a DICT server. DEFINE and MATCH commands, as well as listing of
# databases and strategies are supported.
#
# TODO
# Improve output format


# requires Ruby/DICT <http://www.caliban.org/ruby/ruby-dict.shtml>
begin
  require 'dict'
rescue LoadError
  raise LoadError, "Ruby/DICT not found, grab it from http://www.caliban.org/ruby/ruby-dict.shtml"
end

class ::String
  # Returns a new string truncated to length 'to'
  # If ellipsis is not given, that will just be the first n characters,
  # Else it will return a string in the form <head><ellipsis><tail>
  # The total length of that string will not exceed 'to'.
  # If tail is an Integer, the tail will be exactly 'tail' characters,
  # if it is a Float/Rational tails length will be (to*tail).ceil.
  #
  # Contributed by apeiros
  def truncate(to=32, ellipsis='…', tail=0.3)
    str  = split(//)
    return str.first(to).join('') if !ellipsis or str.length <= to
    to  -= ellipsis.split(//).length
    tail = (tail*to).ceil unless Integer === tail
    to  -= tail
    "#{str.first(to)}#{ellipsis}#{str.last(tail)}"
  end
end

class ::Definition
  def headword
    definition[0].strip
  end

  def body
    # two or more consecutive newlines are replaced with double spaces, while single
    # newlines are replaced with single spaces
    lb = /\r?\n/
    definition[1..-1].join.
      gsub(/\s*(:#{lb}){2,}\s*/, '  ').
      gsub(/\s*#{lb}\s*/, ' ').strip
  end
end

class DictClientPlugin < Plugin
  Config.register Config::StringValue.new('dictclient.server',
    :default => 'dict.org',
    :desc => _('Hostname or hostname:port of the DICT server used to lookup words'))
  Config.register Config::IntegerValue.new('dictclient.max_defs_before_collapse',
    :default => 4,
    :desc => _('When multiple databases reply a number of definitions that above this limit, only the database names will be listed. Otherwise, the full definitions from each database are replied'))
  Config.register Config::IntegerValue.new('dictclient.max_length_per_def',
    :default => 200,
    :desc => _('Each definition is truncated to this length'))
  Config.register Config::StringValue.new('dictclient.headword_format',
    :default => "#{Bold}<headword>#{Bold}",
    :desc => _('Format of headwords; <word> will be replaced with the actual word'))
  Config.register Config::StringValue.new('dictclient.database_format',
    :default => "#{Underline}<database>#{Underline}",
    :desc => _('Format of database names; <database> will be replaced with the database name'))
  Config.register Config::StringValue.new('dictclient.definition_format',
    :default => '<headword>: <definition> -<database>',
    :desc => _('Format of definitions. <word> will be replaced with the formatted headword, <def> will be replaced with the truncated definition, and <database> with the formatted database name'))
  Config.register Config::StringValue.new('dictclient.match_format',
    :default => '<matches>––<database>',
    :desc => _('Format of match results. <matches> will be replaced with the formatted headwords, <database> with the formatted database name'))

  def initialize
    super
  end

  # create a DICT object, which is passed to the block. after the block finishes,
  # the DICT object is automatically disconnected. the return value of the block
  # is returned from this method.
  # if an IRC message argument is passed, the error message will be replied
  def with_dict(m=nil &block)
    server, port = @bot.config['dictclient.server'].split ':' if @bot.config['dictclient.server']
    server ||= 'dict.org'
    port ||= DICT::DEFAULT_PORT
    ret = nil
    begin
      dict = DICT.new(server, port)
      ret = yield dict
      dict.disconnect
    rescue ConnectError
      m.reply _('An error occured connecting to the DICT server. Check the dictclient.server configuration or retry later') if m
    rescue ProtocolError
      m.reply _('A protocol error occured') if m
    rescue DICTError
      m.reply _('An error occured') if m
    end
    ret
  end

  def format_headword(w)
    @bot.config['dictclient.headword_format'].gsub '<headword>', w
  end

  def format_database(d)
    @bot.config['dictclient.database_format'].gsub '<database>', d
  end

  def cmd_define(m, params)
    phrase = params[:phrase].to_s
    results = with_dict(m) {|d| d.define(params[:database], params[:phrase])}
    m.reply(
      if results
        # only list database headers if definitions come from different databases and
        # the number of definitions is above dictclient.max_defs_before_collapse
        if results.any? {|r| r.database != results[0].database} &&
           results.length > @bot.config['dictclient.max_defs_before_collapse']
          _("Many definitions for %{phrase} were found in %{databases}. Use 'define <phrase> from <database> to view a definition.") %
          { :phrase => format_headword(phrase),
            :databases => results.collect {|r| r.database}.uniq.
                                  collect {|d| format_database d}.join(', ') }
        # otherwise display the definitions
        else
          results.collect {|r|
            @bot.config['dictclient.definition_format'].gsub(
              '<headword>', format_headword(r.headword)
            ).gsub(
              '<database>', format_database(r.database)
            ).gsub(
              '<definition>', r.body.truncate(@bot.config['dictclient.max_length_per_def'])
            )
          }.join ' | '
        end
      else
        _("No definition for %{phrase} found from %{database}.") %
          { :phrase => format_headword(phrase),
            :database => format_database(params[:database]) }
      end
    )
  end

  def cmd_match(m, params)
    phrase = params[:phrase].to_s
    results = with_dict(m) {|d| d.match(params[:database],
                                        params[:strategy], phrase)}
    m.reply(
      if results
        results.collect {|database, matches|
          @bot.config['dictclient.match_format'].gsub(
            '<matches>', matches.collect {|m| format_headword m}.join(', ')
          ).gsub(
            '<database>', format_database(database)
          )
        }.join ' '
      else
        _("Nothing matched %{query} from %{database} using %{strategy}") %
        { :query => format_headword(phrase),
          :database => format_database(params[:database]),
          :strategy => params[:strategy] }
      end
    )
  end

  def cmd_databases(m, params)
    with_dict(m) do |d|
      m.reply _("Databases: %{list}") % {
        :list => d.show_db.collect {|db, des| "#{format_database db}: #{des}"}.join(' | ')
      }
    end
  end

  def cmd_strategies(m, params)
    with_dict(m) do |d|
      m.reply _("Strategies: %{list}") % {
        :list => d.show_strat.collect {|s, des| "#{s}: #{des}"}.join(' | ')
      }
    end
  end

  def help(plugin, topic='')
    case topic
    when 'define'
      _('define <phrase> [from <database>] => Show definition of a phrase')
    when 'match'
      _('match <phrase> [using <strategy>] [from <database>] => Show phrases matching the given pattern')
    when 'server information'
      _('dictclient databases => List databases; dictclient strategies => List strategies')
    else
      _('look up phrases on the configured DICT server. topics: define, match, server information')
    end
  end
end

plugin = DictClientPlugin.new

plugin.map 'define *phrase [from :database]',
           :action => 'cmd_define',
           :defaults => {:database => DICT::ALL_DATABASES},
           :threaded => true

plugin.map 'match *phrase [using :strategy] [from :database]',
           :action => 'cmd_match',
           :defaults => {:database => DICT::ALL_DATABASES,
                         :strategy => DICT::DEFAULT_MATCH_STRATEGY },
           :threaded => true

plugin.map 'dictclient databases', :action => 'cmd_databases', :thread => true
plugin.map 'dictclient strategies', :action => 'cmd_strategies', :thread => true
