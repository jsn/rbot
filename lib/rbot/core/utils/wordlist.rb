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
    @@wordlist_base ||= Utils.bot.path 'wordlists'
  end

  def self.get(where, options={})
    opts = { :spaces => false }.merge(options)

    wordlist_path = File.join(wordlist_base, where)
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

    # wordlists are assumed to be UTF-8, but we need to strip the BOM, if present
    wordlist.map! { |l| l.sub("\xef\xbb\xbf",'').strip }
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

  def self.exist?(path)
    fn = path.to_s
    # refuse to check outside of the wordlist base directory
    return false if fn =~ /\.\.\//
    File.exist?(File.join(self.wordlist_base, fn))
  end

end
end
end
