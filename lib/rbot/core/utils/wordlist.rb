#-- vim:sw=2:et
#++
#
# :title: rbot wordlist provider
#
# Author:: Raine Virta <rane@kapsi.fi>

require "find"

module ::Irc
class Bot
class Wordlist
  def self.wordlist_base
    @@wordlist_base ||= File.join(Utils.bot.botclass, 'wordlists')
  end

  def self.get(path, options={})
    opts = { :spaces => false }.merge(options)

    wordlist_path = File.join(wordlist_base, path)
    raise "wordlist not found: #{wordlist_path}" unless File.exist?(wordlist_path)

    # Location is a directory -> combine all lists beneath it
    wordlist = if File.directory?(wordlist_path)
      wordlists = []
      Find.find(wordlist_path) do |path|
        next if path == wordlist_path
        wordlists << path unless File.directory?(path)
      end

      wordlists.map { |list| File.readlines(list) }.flatten
    else
      File.readlines(wordlist_path)
    end

    wordlist.map! { |l| l.strip }
    wordlist.reject do |word|
      word =~ /\s/ && !opts[:spaces] ||
      word.empty?
    end
  end

  # Return an array with the list of available wordlists.
  # Available options:
  # pattern:: pattern that should be matched by the wordlist filename
  def self.list(options={})
    pattern = options[:pattern] || "**"
    # refuse patterns that contain ../
    return [] if pattern =~ /\.\.\//
    striplen = self.wordlist_base.length+1
    Dir.glob(File.join(self.wordlist_base, pattern)).map { |name|
      name[striplen..-1]
    }
  end
end
end
end
