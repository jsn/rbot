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
            forms.name('translateForm').first
  end

  def do_translate(text, from, to)
    @form.radiobuttons.name('langpair').value = "#{from},#{to}".upcase
    @form.fields.name('sourceText').value = text

    @form.submit(@form.buttons.name('translate')).
          forms.name('translateForm').fields.name('translatedText').value
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
                   forms.name('world').first
  end

  def do_translate(text, from, to)
    non_ja_language = from != 'ja' ? from : to
    form = @forms[non_ja_language]

    if non_ja_language =~ /zh_(CN|TW)/
      form.fields.name('wb_lp').value = "#{from}#{to}".sub(/_(?:CN|TW)/, '').upcase
      form.fields.name('big5').value = ($1 == 'TW' ? 'yes' : 'no')
    else
      # the en<->ja page is in Shift_JIS while other pages are UTF-8
      text = Iconv.iconv('Shift_JIS', 'UTF-8', text) if non_ja_language == 'en'
      form.fields.name('wb_lp').value = "#{from}#{to}".upcase
    end
    form.fields.name('before').value = text
    result = form.submit.forms.name('world').fields.name('after').value
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
    language_pairs = @lang_list.options.map do |o|
      # these options have values like "en|zh-CN"; map to things like ['en', 'zh_CN'].
      o.value.split('|').map {|l| l.sub('-', '_')}
    end
    super(Translator::Direction.pairs(language_pairs), cache)
  end

  def load_form!
    agent = WWW::Mechanize.new
    # without faking the user agent, Google Translate will serve non-UTF-8 text
    agent.user_agent_alias = 'Linux Konqueror'
    @form = agent.get('http://www.google.com/translate_t').
            forms.action('/translate_t').first
    @lang_list = @form.fields.name('langpair')
  end

  def do_translate(text, from, to)
    load_form!

    @lang_list.value = "#{from}|#{to}".sub('_', '-')
    @form.fields.name('text').value = text
    @form.submit.parser.search('div#result_box').inner_html
  end
end


class BabelfishTranslator < Translator
  INFO = 'AltaVista Babel Fish Translation <http://babelfish.altavista.com/babelfish/>'

  def initialize(cache)
    require 'mechanize'

    @form = WWW::Mechanize.new.get('http://babelfish.altavista.com/babelfish/').
            forms.name('frmTrText').first
    @lang_list = @form.fields.name('lp')
    language_pairs = @lang_list.options.map {|o| o.value.split('_')}.
                                            reject {|p| p.empty?}
    super(Translator::Direction.pairs(language_pairs), cache)
  end

  def do_translate(text, from, to)
    if @form.fields.name('trtext').empty?
      @form.add_field!('trtext', text)
    else
      @form.fields.name('trtext').value = text
    end
    @lang_list.value = "#{from}_#{to}"
    @form.submit.parser.search("td.s/div[@style]").inner_html
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
  BotConfig.register BotConfigIntegerValue.new('translator.timeout',
    :default => 30, :validate => Proc.new{|v| v > 0},
    :desc => _("Number of seconds to wait for the translation service before timeout"))

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
        map "#{name} :from :to *phrase", :action => :cmd_translate
      rescue Exception
        warning _("Translator %{name} cannot be used: %{reason}") %
               {:name => name, :reason => $!}
      end
    end

    BotConfig.register BotConfigArrayValue.new('translator.default_list',
      :default => TRANSLATORS.keys,
      :validate => Proc.new {|l| l.all? {|t| TRANSLATORS.has_key?(t)}},
      :desc => _("List of translators to try in order when translator name not specified"),
      :on_change => Proc.new {|bot, v| update_default})
    update_default
  end

  def help(plugin, topic=nil)
    if @translators.has_key?(topic)
      translator = @translators[topic]
      _('%{info}, supported directions of translation: %{directions}') % {
        :info => translator.class::INFO,
        :directions => translator.directions.map do |source, targets|
                         _('%{source} -> %{targets}') %
                         {:source => source, :targets => targets.to_a.join(', ')}
                       end.join(' | ')
      }
    else
      _('Command: <translator> <from> <to> <phrase>, where <translator> is one of: %{translators}. If "translator" is used in place of the translator name, the first translator in translator.default_list which supports the specified direction will be picked automatically. Use "help translator <translator>" to look up supported from and to languages') %
        {:translators => @translators.keys.join(', ')}
    end
  end

  def update_default
    @default_translators = bot.config['translator.default_list'] & @translators.keys 
  end

  def cmd_translator(m, params)
    from, to = params[:from], params[:to]
    translator = @default_translators.find {|t| @translators[t].support?(from, to)}
    if translator
      cmd_translate m, params.merge({:translator => translator})
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
        m.reply translation
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
plugin.map 'translator :from :to *phrase', :action => :cmd_translator
