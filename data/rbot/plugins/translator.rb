#-- vim:sw=2:et
#++
#
# :title: Translator plugin for rbot
#
# Author:: Yaohan Chen <yaohan.chen@gmail.com>
# Copyright:: (C) 2007 Yaohan Chen
# License:: GPLv2
#
# This plugin allows using rbot to translate text on a few translation services
#
# TODO
#
# * Configuration for whether to show translation engine
# * Optionally sync default translators with karma.rb ranking

require 'set'
require 'timeout'

# base class for implementing a translation service
# = Attributes
# direction:: supported translation directions, a hash where each key is a source
#             language name, and each value is Set of target language names. The
#             methods in the Direction module are convenient for initializing this
#             attribute
class Translator
  INFO = 'Some translation service'

  class UnsupportedDirectionError < ArgumentError
  end

  class NoTranslationError < RuntimeError
  end

  attr_reader :directions, :cache

  def initialize(directions, cache={})
    @directions = directions
    @cache = cache
  end


  # whether the translator supports this direction
  def support?(from, to)
    from != to && @directions[from].include?(to)
  end

  # this implements argument checking and caching. subclasses should define the
  # do_translate method to implement actual translation
  def translate(text, from, to)
    raise UnsupportedDirectionError unless support?(from, to)
    raise ArgumentError, _("Cannot translate empty string") if text.empty?
    request = [text, from, to]
    unless @cache.has_key? request
      translation = do_translate(text, from, to)
      raise NoTranslationError if translation.empty?
      @cache[request] = translation
    else
      @cache[request]
    end
  end

  module Direction
    # given the set of supported languages, return a hash suitable for the directions
    # attribute which includes any language to any other language
    def self.all_to_all(languages)
      directions = all_to_none(languages)
      languages.each {|l| directions[l] = languages.to_set}
      directions
    end

    # a hash suitable for the directions attribute which includes any language from/to
    # the given set of languages (center_languages)
    def self.all_from_to(languages, center_languages)
      directions = all_to_none(languages)
      center_languages.each {|l| directions[l] = languages - [l]}
      (languages - center_languages).each {|l| directions[l] = center_languages.to_set}
      directions
    end

    # get a hash from a list of pairs
    def self.pairs(list_of_pairs)
      languages = list_of_pairs.flatten.to_set
      directions = all_to_none(languages)
      list_of_pairs.each do |(from, to)|
        directions[from] << to
      end
      directions
    end

    # an empty hash with empty sets as default values
    def self.all_to_none(languages)
      Hash.new do |h, k|
        # always return empty set when the key is non-existent, but put empty set in the
        # hash only if the key is one of the languages
        if languages.include? k
          h[k] = Set.new
        else
          Set.new
        end
      end
    end
  end
end


class NiftyTranslator < Translator
  INFO = '@nifty Translation <http://nifty.amikai.com/amitext/indexUTF8.jsp>'

  def initialize(cache={})
   require 'mechanize'
   super(Translator::Direction.all_from_to(%w[ja en zh_CN ko], %w[ja]), cache)
    @form = WWW::Mechanize.new.
            get('http://nifty.amikai.com/amitext/indexUTF8.jsp').
            forms_with(:name => 'translateForm').last
  end

  def do_translate(text, from, to)
    @radio = @form.radiobuttons_with(:name => 'langpair').first
    @radio.value = "#{from},#{to}".upcase
    @radio.check
    @form.fields_with(:name => 'sourceText').last.value = text

    @form.submit(@form.buttons_with(:name => 'translate').last).
          forms_with(:name => 'translateForm').last.fields_with(:name => 'translatedText').last.value
  end
end


class ExciteTranslator < Translator
  INFO = 'Excite.jp Translation <http://www.excite.co.jp/world/>'

  def initialize(cache={})
    require 'mechanize'
    require 'iconv'

    super(Translator::Direction.all_from_to(%w[ja en zh_CN zh_TW ko], %w[ja]), cache)

    @forms = Hash.new do |h, k|
      case k
      when 'en'
        h[k] = open_form('english')
      when 'zh_CN', 'zh_TW'
        # this way we don't need to fetch the same page twice
        h['zh_CN'] = h['zh_TW'] = open_form('chinese')
      when 'ko'
        h[k] = open_form('korean')
      end
    end
  end

  def open_form(name)
    WWW::Mechanize.new.get("http://www.excite.co.jp/world/#{name}").
                   forms_with(:name => 'world').first
  end

  def do_translate(text, from, to)
    non_ja_language = from != 'ja' ? from : to
    form = @forms[non_ja_language]

    if non_ja_language =~ /zh_(CN|TW)/
      form_with_fields(:name => 'wb_lp').first.value = "#{from}#{to}".sub(/_(?:CN|TW)/, '').upcase
      form_with_fields(:name => 'big5').first.value = ($1 == 'TW' ? 'yes' : 'no')
    else
      # the en<->ja page is in Shift_JIS while other pages are UTF-8
      text = Iconv.iconv('Shift_JIS', 'UTF-8', text) if non_ja_language == 'en'
      form.fields_with(:name => 'wb_lp').first.value = "#{from}#{to}".upcase
    end
    form.fields_with(:name => 'before').first.value = text
    result = form.submit.forms_with(:name => 'world').first.fields_with(:name => 'after').first.value
    # the en<->ja page is in Shift_JIS while other pages are UTF-8
    if non_ja_language == 'en'
      Iconv.iconv('UTF-8', 'Shift_JIS', result)
    else
      result
    end

  end
end


class GoogleTranslator < Translator
  INFO = 'Google Translate <http://www.google.com/translate_t>'

  def initialize(cache={})
    require 'mechanize'
    load_form!

    # we can probably safely assume that google translate is able to translate from
    # any language in the source lang drop down list to any language in the target one
    # so we create the language pairs based on that assumption
    sl = @source_list.options.map { |o| o.value.sub('-', '_') }
    tl = @target_list.options.map { |o| o.value.sub('-', '_') }
    super(Translator::Direction.all_from_to(tl, sl), cache)
  end

  def load_form!
    agent = WWW::Mechanize.new
    # without faking the user agent, Google Translate will serve non-UTF-8 text
    agent.user_agent_alias = 'Linux Konqueror'
    @form = agent.get('http://www.google.com/translate_t').
            forms_with(:action => '/translate_t').first
    @source_list = @form.fields_with(:name => 'sl').last
    @target_list = @form.fields_with(:name => 'tl').last
  end

  def do_translate(text, from, to)
    load_form!

    @source_list.value = from.sub('_', '-')
    @target_list.value = to.sub('_', '-')
    @form.fields_with(:name => 'text').last.value = text
    @form.submit.parser.search('div#result_box').inner_html
  end
end


class BabelfishTranslator < Translator
  INFO = 'AltaVista Babel Fish Translation <http://babelfish.altavista.com/babelfish/>'

  def initialize(cache)
    require 'mechanize'

    @form = WWW::Mechanize.new.get('http://babelfish.altavista.com/babelfish/').
            forms_with(:name => 'frmTrText').first
    @lang_list = @form.fields_with(:name => 'lp').first
    language_pairs = @lang_list.options.map {|o| o.value.split('_')}.
                                            reject {|p| p.empty?}
    super(Translator::Direction.pairs(language_pairs), cache)
  end

  def do_translate(text, from, to)
    if @form.fields_with(:name => 'trtext').empty?
      @form.add_field!('trtext', text)
    else
      @form.fields_with(:name => 'trtext').first.value = text
    end
    @lang_list.value = "#{from}_#{to}"
    @form.submit.parser.search("div[@id='result']/div[@style]").inner_html
  end
end

class WorldlingoTranslator < Translator
  INFO = 'WorldLingo Free Online Translator <http://www.worldlingo.com/en/products_services/worldlingo_translator.html>'

  LANGUAGES = %w[en fr de it pt es ru nl el sv ar ja ko zh_CN zh_TW]
  def initialize(cache)
    require 'uri'
    super(Translator::Direction.all_to_all(LANGUAGES), cache)
  end

  def translate(text, from, to)
    response = Irc::Utils.bot.httputil.get_response(URI.escape(
               "http://www.worldlingo.com/SEfpX0LV2xIxsIIELJ,2E5nOlz5RArCY,/texttranslate?wl_srcenc=utf-8&wl_trgenc=utf-8&wl_text=#{text}&wl_srclang=#{from.upcase}&wl_trglang=#{to.upcase}"))
    # WorldLingo seems to respond an XML when error occurs
    case response['Content-Type']
    when %r'text/plain'
      response.body
    else
      raise Translator::NoTranslationError
    end
  end
end

class TranslatorPlugin < Plugin
  Config.register Config::IntegerValue.new('translator.timeout',
    :default => 30, :validate => Proc.new{|v| v > 0},
    :desc => _("Number of seconds to wait for the translation service before timeout"))
  Config.register Config::StringValue.new('translator.destination',
    :default => "en",
    :desc => _("Default destination language to be used with translate command"))

  TRANSLATORS = {
    'nifty' => NiftyTranslator,
    'excite' => ExciteTranslator,
    'google_translate' => GoogleTranslator,
    'babelfish' => BabelfishTranslator,
    'worldlingo' => WorldlingoTranslator,
  }

  def initialize
    super

    @translators = {}
    TRANSLATORS.each_pair do |name, c|
      begin
        @translators[name] = c.new(@registry.sub_registry(name))
        map "#{name} :from :to *phrase",
          :action => :cmd_translate, :thread => true
      rescue Exception
        warning _("Translator %{name} cannot be used: %{reason}") %
               {:name => name, :reason => $!}
      end
    end

    Config.register Config::ArrayValue.new('translator.default_list',
      :default => TRANSLATORS.keys,
      :validate => Proc.new {|l| l.all? {|t| TRANSLATORS.has_key?(t)}},
      :desc => _("List of translators to try in order when translator name not specified"),
      :on_change => Proc.new {|bot, v| update_default})
    update_default
  end

  def help(plugin, topic=nil)
    if @translators.has_key?(plugin)
      translator = @translators[plugin]
      _('%{translator} <from> <to> <phrase> => Look up phrase using %{info}, supported from -> to languages: %{directions}') % {
        :translator => plugin,
        :info => translator.class::INFO,
        :directions => translator.directions.map do |source, targets|
                         _('%{source} -> %{targets}') %
                         {:source => source, :targets => targets.to_a.join(', ')}
                       end.join(' | ')
      }
    else
      _('Command: <translator> <from> <to> <phrase>, where <translator> is one of: %{translators}. If "translator" is used in place of the translator name, the first translator in translator.default_list which supports the specified direction will be picked automatically. Use "help <translator>" to look up supported from and to languages') %
        {:translators => @translators.keys.join(', ')}
    end
  end

  def languages
    @languages ||= @translators.map { |t| t.last.directions.keys }.flatten.uniq
  end

  def update_default
    @default_translators = bot.config['translator.default_list'] & @translators.keys
  end

  def cmd_translator(m, params)
    params[:to] = @bot.config['translator.destination'] if params[:to].nil?

    # Use google translate as translator if source language has not been given
    # and auto-detect it
    if params[:from].nil?
      params[:from] = "auto"
      translator = "google_translate"
    else
      translator = @default_translators.find {|t| @translators[t].support?(params[:from], params[:to])}
    end

    if translator
      cmd_translate m, params.merge({:translator => translator, :show_provider => true})
    else
      m.reply _('None of the default translators (translator.default_list) supports translating from %{source} to %{target}') % {:source => from, :target => to}
    end
  end

  def cmd_translate(m, params)
    # get the first word of the command
    tname = params[:translator] || m.message[/\A(\w+)\s/, 1]
    translator = @translators[tname]
    from, to, phrase = params[:from], params[:to], params[:phrase].to_s
    if translator
      begin
        translation = Timeout.timeout(@bot.config['translator.timeout']) do
          translator.translate(phrase, from, to)
        end
        m.reply(if params[:show_provider]
                  _('%{translation} (provided by %{translator})') %
                    {:translation => translation, :translator => tname.gsub("_", " ")}
                else
                  translation
                end)

      rescue Translator::UnsupportedDirectionError
        m.reply _("%{translator} doesn't support translating from %{source} to %{target}") %
                {:translator => tname, :source => from, :target => to}
      rescue Translator::NoTranslationError
        m.reply _('%{translator} failed to provide a translation') %
                {:translator => tname}
      rescue Timeout::Error
        m.reply _('The translator timed out')
      end
    else
      m.reply _('No translator called %{name}') % {:name => tname}
    end
  end
end

plugin = TranslatorPlugin.new
req = Hash[*%w(from to).map { |e| [e.to_sym, /#{plugin.languages.join("|")}/] }.flatten]

plugin.map 'translate [:from] [:to] *phrase',
           :action => :cmd_translator, :thread => true, :requirements => req
plugin.map 'translator [:from] [:to] *phrase',
           :action => :cmd_translator, :thread => true, :requirements => req
