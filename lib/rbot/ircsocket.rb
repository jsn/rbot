class ::String
  # Calculate the penalty which will be assigned to this message
  # by the IRCd
  def irc_send_penalty
    # According to eggrdop, the initial penalty is
    penalty = 1 + self.size/100
    # on everything but UnderNET where it's
    # penalty = 2 + self.size/120

    cmd, pars = self.split($;,2)
    debug "cmd: #{cmd}, pars: #{pars.inspect}"
    case cmd.to_sym
    when :KICK
      chan, nick, msg = pars.split
      chan = chan.split(',')
      nick = nick.split(',')
      penalty += nick.size
      penalty *= chan.size
    when :MODE
      chan, modes, argument = pars.split
      extra = 0
      if modes
        extra = 1
        if argument
          extra += modes.split(/\+|-/).size
        else
          extra += 3 * modes.split(/\+|-/).size
        end
      end
      if argument
        extra += 2 * argument.split.size
      end
      penalty += extra * chan.split.size
    when :TOPIC
      penalty += 1
      penalty += 2 unless pars.split.size < 2
    when :PRIVMSG, :NOTICE
      dests = pars.split($;,2).first
      penalty += dests.split(',').size
    when :WHO
      # I'm too lazy to implement this one correctly
      penalty += 5
    when :AWAY, :JOIN, :VERSION, :TIME, :TRACE, :WHOIS, :DNS
      penalty += 2
    when :INVITE, :NICK
      penalty += 3
    when :ISON
      penalty += 1
    else # Unknown messages
      penalty += 1
    end
    if penalty > 99
      debug "Wow, more than 99 secs of penalty!"
      penalty = 99
    end
    if penalty < 2
      debug "Wow, less than 2 secs of penalty!"
      penalty = 2
    end
    debug "penalty: #{penalty}"
    return penalty
  end
end

module Irc

  require 'socket'
  require 'thread'
  require 'rbot/timer'

  class QueueRing
    # A QueueRing is implemented as an array with elements in the form
    # [chan, [message1, message2, ...]
    # Note that the channel +chan+ has no actual bearing with the channels
    # to which messages will be sent

    def initialize
      @storage = Array.new
      @last_idx = -1
    end

    def clear
      @storage.clear
      @last_idx = -1
    end

    def length
      len = 0
      @storage.each {|c|
        len += c[1].size
      }
      return len
    end
    alias :size :length

    def empty?
      @storage.empty?
    end

    def push(mess, chan)
      cmess = @storage.assoc(chan)
      if cmess
        idx = @storage.index(cmess)
        cmess[1] << mess
        @storage[idx] = cmess
      else
        @storage << [chan, [mess]]
      end
    end

    def next
      if empty?
        warning "trying to access empty ring"
        return nil
      end
      save_idx = @last_idx
      @last_idx = (@last_idx + 1) % @storage.size
      mess = @storage[@last_idx][1].first
      @last_idx = save_idx
      return mess
    end

    def shift
      if empty?
        warning "trying to access empty ring"
        return nil
      end
      @last_idx = (@last_idx + 1) % @storage.size
      mess = @storage[@last_idx][1].shift
      @storage.delete(@storage[@last_idx]) if @storage[@last_idx][1] == []
      return mess
    end

  end

  class MessageQueue
    def initialize
      # a MessageQueue is an array of QueueRings
      # rings have decreasing priority, so messages in ring 0
      # are more important than messages in ring 1, and so on
      @rings = Array.new(3) { |i|
        if i > 0
          QueueRing.new
        else
          # ring 0 is special in that if it's not empty, it will
          # be popped. IOW, ring 0 can starve the other rings
          # ring 0 is strictly FIFO and is therefore implemented
          # as an array
          Array.new
        end
      }
      # the other rings are satisfied round-robin
      @last_ring = 0
    end

    def clear
      @rings.each { |r|
        r.clear
      }
      @last_ring = 0
    end

    def push(mess, chan=nil, cring=0)
      ring = cring
      if ring == 0
        warning "message #{mess} at ring 0 has channel #{chan}: channel will be ignored" if !chan.nil?
        @rings[0] << mess
      else
        error "message #{mess} at ring #{ring} must have a channel" if chan.nil?
        @rings[ring].push mess, chan
      end
    end

    def empty?
      @rings.each { |r|
        return false unless r.empty?
      }
      return true
    end

    def length
      len = 0
      @rings.each { |r|
        len += r.size
      }
      len
    end
    alias :size :length

    def next
      if empty?
        warning "trying to access empty ring"
        return nil
      end
      mess = nil
      if !@rings[0].empty?
        mess = @rings[0].first
      else
        save_ring = @last_ring
        (@rings.size - 1).times {
          @last_ring = (@last_ring % (@rings.size - 1)) + 1
          if !@rings[@last_ring].empty?
            mess = @rings[@last_ring].next
            break
          end
        }
        @last_ring = save_ring
      end
      error "nil message" if mess.nil?
      return mess
    end

    def shift
      if empty?
        warning "trying to access empty ring"
        return nil
      end
      mess = nil
      if !@rings[0].empty?
        return @rings[0].shift
      end
      (@rings.size - 1).times {
        @last_ring = (@last_ring % (@rings.size - 1)) + 1
        if !@rings[@last_ring].empty?
          return @rings[@last_ring].shift
        end
      }
      error "nil message" if mess.nil?
      return mess
    end

  end

  # wrapped TCPSocket for communication with the server.
  # emulates a subset of TCPSocket functionality
  class IrcSocket

    MAX_IRC_SEND_PENALTY = 10

    # total number of lines sent to the irc server
    attr_reader :lines_sent

    # total number of lines received from the irc server
    attr_reader :lines_received

    # total number of bytes sent to the irc server
    attr_reader :bytes_sent

    # total number of bytes received from the irc server
    attr_reader :bytes_received

    # accumulator for the throttle
    attr_reader :throttle_bytes

    # delay between lines sent
    attr_reader :sendq_delay

    # max lines to burst
    attr_reader :sendq_burst

    # an optional filter object. we call @filter.in(data) for
    # all incoming data and @filter.out(data) for all outgoing data
    attr_reader :filter

    # normalized uri of the current server
    attr_reader :server_uri

    # default trivial filter class
    class IdentityFilter
        def in(x)
            x
        end

        def out(x)
            x
        end
    end

    # set filter to identity, not to nil
    def filter=(f)
        @filter = f || IdentityFilter.new
    end

    # server_list:: list of servers to connect to
    # host::   optional local host to bind to (ruby 1.7+ required)
    # create a new IrcSocket
    def initialize(server_list, host, sendq_delay=2, sendq_burst=4, opts={})
      @timer = Timer::Timer.new
      @timer.add(0.2) do
        spool
      end
      @server_list = server_list.dup
      @server_uri = nil
      @conn_count = 0
      @host = host
      @sock = nil
      @filter = IdentityFilter.new
      @spooler = false
      @lines_sent = 0
      @lines_received = 0
      if opts.kind_of?(Hash) and opts.key?(:ssl)
        @ssl = opts[:ssl]
      else
        @ssl = false
      end

      if sendq_delay
        @sendq_delay = sendq_delay.to_f
      else
        @sendq_delay = 2
      end
      @last_send = Time.new - @sendq_delay
      @flood_send = Time.new
      @last_throttle = Time.new
      @burst = 0
      if sendq_burst
        @sendq_burst = sendq_burst.to_i
      else
        @sendq_burst = 4
      end
    end

    def connected?
      !@sock.nil?
    end

    # open a TCP connection to the server
    def connect
      if connected?
        warning "reconnecting while connected"
        return
      end
      srv_uri = @server_list[@conn_count % @server_list.size].dup
      srv_uri = 'irc://' + srv_uri if !(srv_uri =~ /:\/\//)
      @conn_count += 1
      @server_uri = URI.parse(srv_uri)
      @server_uri.port = 6667 if !@server_uri.port
      debug "connection attempt \##{@conn_count} (#{@server_uri.host}:#{@server_uri.port})"

      if(@host)
        begin
          @sock=TCPSocket.new(@server_uri.host, @server_uri.port, @host)
        rescue ArgumentError => e
          error "Your version of ruby does not support binding to a "
          error "specific local address, please upgrade if you wish "
          error "to use HOST = foo"
          error "(this option has been disabled in order to continue)"
          @sock=TCPSocket.new(@server_uri.host, @server_uri.port)
        end
      else
        @sock=TCPSocket.new(@server_uri.host, @server_uri.port)
      end
      if(@ssl)
        require 'openssl'
        ssl_context = OpenSSL::SSL::SSLContext.new()
        ssl_context.verify_mode = OpenSSL::SSL::VERIFY_NONE
        @rawsock = @sock
        @sock = OpenSSL::SSL::SSLSocket.new(@rawsock, ssl_context)
        @sock.sync_close = true
        @sock.connect
      end
      @qthread = false
      @qmutex = Mutex.new
      @sendq = MessageQueue.new
    end

    def sendq_delay=(newfreq)
      debug "changing sendq frequency to #{newfreq}"
      @qmutex.synchronize do
        @sendq_delay = newfreq
        if newfreq == 0
          clearq
          @timer.stop
        else
          @timer.start
        end
      end
    end

    def sendq_burst=(newburst)
      @qmutex.synchronize do
        @sendq_burst = newburst
      end
    end

    # used to send lines to the remote IRCd by skipping the queue
    # message: IRC message to send
    # it should only be used for stuff that *must not* be queued,
    # i.e. the initial PASS, NICK and USER command
    # or the final QUIT message
    def emergency_puts(message)
      @qmutex.synchronize do
        # debug "In puts - got mutex"
        puts_critical(message)
      end
    end

    def handle_socket_error(string, err)
      error "#{string} failed: #{err.inspect}"
      debug err.backtrace.join("\n")
      # We assume that an error means that there are connection
      # problems and that we should reconnect, so we
      shutdown
      raise SocketError.new(err.inspect)
    end

    # get the next line from the server (blocks)
    def gets
      if @sock.nil?
        warning "socket get attempted while closed"
        return nil
      end
      begin
        reply = @filter.in(@sock.gets)
        @lines_received += 1
        reply.strip! if reply
        debug "RECV: #{reply.inspect}"
        return reply
      rescue => e
        handle_socket_error(:RECV, e)
      end
    end

    def queue(msg, chan=nil, ring=0)
      if @sendq_delay > 0
        @qmutex.synchronize do
          @sendq.push msg, chan, ring
          @timer.start
        end
      else
        # just send it if queueing is disabled
        self.emergency_puts(msg)
      end
    end

    # pop a message off the queue, send it
    def spool
      @qmutex.synchronize do
        begin
          debug "in spooler"
          if @sendq.empty?
            @timer.stop
            return
          end
          now = Time.new
          if (now >= (@last_send + @sendq_delay))
            debug "resetting @burst"
            @burst = 0
          elsif (@burst > @sendq_burst)
            # nope. can't send anything, come back to us next tick...
            debug "can't send yet"
            @timer.start
            return
          end
          @flood_send = now if @flood_send < now
          debug "can send #{@sendq_burst - @burst} lines, there are #{@sendq.size} to send"
          while !@sendq.empty? and @burst < @sendq_burst and @flood_send - now < MAX_IRC_SEND_PENALTY
            debug "sending message (#{@flood_send - now} < #{MAX_IRC_SEND_PENALTY})"
            puts_critical(@sendq.shift, true)
          end
          if @sendq.empty?
            @timer.stop
          end
        rescue => e
          error "Spooling failed: #{e.inspect}"
          error e.backtrace.join("\n")
        end
      end
    end

    def clearq
      if @sock
        @qmutex.synchronize do
          unless @sendq.empty?
            @sendq.clear
          end
        end
      else
        warning "Clearing socket while disconnected"
      end
    end

    # flush the TCPSocket
    def flush
      @sock.flush
    end

    # Wraps Kernel.select on the socket
    def select(timeout=nil)
      Kernel.select([@sock], nil, nil, timeout)
    end

    # shutdown the connection to the server
    def shutdown(how=2)
      return unless connected?
      begin
        @sock.close
      rescue => err
        error "error while shutting down: #{err.inspect}"
        debug err.backtrace.join("\n")
      end
      @rawsock = nil if @ssl
      @sock = nil
      @burst = 0
    end

    private

    # same as puts, but expects to be called with a mutex held on @qmutex
    def puts_critical(message, penalty=false)
      # debug "in puts_critical"
      begin
        debug "SEND: #{message.inspect}"
        if @sock.nil?
          error "SEND attempted on closed socket"
        else
          @sock.puts(@filter.out(message))
          @last_send = Time.new
          @flood_send += message.irc_send_penalty if penalty
          @lines_sent += 1
          @burst += 1
        end
      rescue => e
        handle_socket_error(:SEND, e)
      end
    end

  end

end
