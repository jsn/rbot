# Copyright (C) 2002 Tom Gilbert.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to
# deal in the Software without restriction, including without limitation the
# rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
# sell copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies of the Software and its documentation and acknowledgment shall be
# given in the documentation and software packages that this Software was
# used.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
# THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
# IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
# CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

require 'bdb'
# make BTree lookups case insensitive
module BDB
  class CIBtree < Btree
    def bdb_bt_compare(a, b)
      a.downcase <=> b.downcase
    end
  end
end

module Irc

  # DBHash is for tying a hash to disk (using bdb).
  # Call it with an identifier, for example "mydata". It'll look for
  # mydata.db, if it exists, it will load and reference that db.
  # Otherwise it'll create and empty db called mydata.db
  class DBHash
    
    # absfilename:: use +key+ as an actual filename, don't prepend the bot's
    #               config path and don't append ".db"
    def initialize(bot, key, absfilename=false)
      @bot = bot
      @key = key
      if absfilename && File.exist?(key)
        # db already exists, use it
        @db = DBHash.open_db(key)
      elsif File.exist?(@bot.botclass + "/#{key}.db")
        # db already exists, use it
        @db = DBHash.open_db(@bot.botclass + "/#{key}.db")
      elsif absfilename
        # create empty db
        @db = DBHash.create_db(key)
      else
        # create empty db
        @db = DBHash.create_db(@bot.botclass + "/#{key}.db")
      end
    end

    def method_missing(method, *args, &block)
      return @db.send(method, *args, &block)
    end

    def DBHash.create_db(name)
      debug "DBHash: creating empty db #{name}"
      return BDB::Hash.open(name, nil, 
                             BDB::CREATE | BDB::EXCL | BDB::TRUNCATE,
                             0600, "set_pagesize" => 1024,
                             "set_cachesize" => [(0), (32 * 1024), (0)])
    end

    def DBHash.open_db(name)
      debug "DBHash: opening existing db #{name}"
      return BDB::Hash.open(name, nil, 
                             "r+", 0600, "set_pagesize" => 1024,
                             "set_cachesize" => [(0), (32 * 1024), (0)])
    end
    
  end

  
  # DBTree is a BTree equivalent of DBHash, with case insensitive lookups.
  class DBTree
    
    # absfilename:: use +key+ as an actual filename, don't prepend the bot's
    #               config path and don't append ".db"
    def initialize(bot, key, absfilename=false)
      @bot = bot
      @key = key
      if absfilename && File.exist?(key)
        # db already exists, use it
        @db = DBTree.open_db(key)
      elsif absfilename
        # create empty db
        @db = DBTree.create_db(key)
      elsif File.exist?(@bot.botclass + "/#{key}.db")
        # db already exists, use it
        @db = DBTree.open_db(@bot.botclass + "/#{key}.db")
      else
        # create empty db
        @db = DBTree.create_db(@bot.botclass + "/#{key}.db")
      end
    end

    def method_missing(method, *args, &block)
      return @db.send(method, *args, &block)
    end

    def DBTree.create_db(name)
      debug "DBTree: creating empty db #{name}"
      return BDB::CIBtree.open(name, nil, 
                             BDB::CREATE | BDB::EXCL | BDB::TRUNCATE,
                             0600, "set_pagesize" => 1024,
                             "set_cachesize" => [(0), (32 * 1024), (0)])
    end

    def DBTree.open_db(name)
      debug "DBTree: opening existing db #{name}"
      return BDB::CIBtree.open(name, nil, 
                             "r+", 0600, "set_pagesize" => 1024,
                             "set_cachesize" => [0, 32 * 1024, 0])
    end
    
  end

end
