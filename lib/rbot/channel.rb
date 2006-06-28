module Irc

  # class to store IRC channel data (users, topic, per-channel configurations)
  class IRCChannel
    # name of channel
    attr_reader :name

    # current channel topic
    attr_reader :topic

    # hash containing users currently in the channel
    attr_accessor :users

    # if true, bot won't talk in this channel
    attr_accessor :quiet

    # name:: channel name
    # create a new IRCChannel
    def initialize(name)
      @name = name
      @users = Hash.new
      @quiet = false
      @topic = Topic.new
    end

    # eg @bot.channels[chan].topic = topic
    def topic=(name)
      @topic.name = name
    end

    # class to store IRC channel topic information
    class Topic
      # topic name
      attr_accessor :name

      # timestamp
      attr_accessor :timestamp

      # topic set by
      attr_accessor :by

      def initialize
        @name = ""
      end

      # when called like "puts @bots.channels[chan].topic"
      def to_s
        @name
      end
    end

  end

end
