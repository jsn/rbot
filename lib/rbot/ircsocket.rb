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
      length = 0
      @storage.each {|c|
        length += c[1].length 
      }
      return length
    end

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
      @last_idx = (@last_idx + 1) % @storage.length
      mess = @storage[@last_idx][1].first
      @last_idx = save_idx
      return mess
    end

    def shift
      if empty?
        warning "trying to access empty ring"
        return nil
      end
      @last_idx = (@last_idx + 1) % @storage.length
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
        len += r.length
      }
      len
    end

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
        (@rings.length - 1).times {
          @last_ring = (@last_ring % (@rings.length - 1)) + 1
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
      (@rings.length - 1).times {
        @last_ring = (@last_ring % (@rings.length - 1)) + 1
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

    # byterate components
    attr_reader :bytes_per
    attr_reader :seconds_per

    # delay between lines sent
    attr_reader :sendq_delay

    # max lines to burst
    attr_reader :sendq_burst

    # server:: server to connect to
    # port::   IRCd port
    # host::   optional local host to bind to (ruby 1.7+ required)
    # create a new IrcSocket
    def initialize(server, port, host, sendq_delay=2, sendq_burst=4, brt="400/2")
      @timer = Timer::Timer.new
      @timer.add(0.2) do
        spool
      end
      @server = server.dup
      @port = port.to_i
      @host = host
      @sock = nil
      @spooler = false
      @lines_sent = 0
      @lines_received = 0
      if sendq_delay
        @sendq_delay = sendq_delay.to_f
      else
        @sendq_delay = 2
      end
      @last_send = Time.new - @sendq_delay
      @last_throttle = Time.new
      @burst = 0
      if sendq_burst
        @sendq_burst = sendq_burst.to_i
      else
        @sendq_burst = 4
      end
      @bytes_per = 400
      @seconds_per = 2
      @throttle_bytes = 0
      @throttle_div = 1
      setbyterate(brt)
    end

    def setbyterate(brt)
      if brt.match(/(\d+)\/(\d)/)
        @bytes_per = $1.to_i
        @seconds_per = $2.to_i
        debug "Byterate now #{byterate}"
        return true
      else
        debug "Couldn't set byterate #{brt}"
        return false
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
      if(@host)
        begin
          @sock=TCPSocket.new(@server, @port, @host)
        rescue ArgumentError => e
          error "Your version of ruby does not support binding to a "
          error "specific local address, please upgrade if you wish "
          error "to use HOST = foo"
          error "(this option has been disabled in order to continue)"
          @sock=TCPSocket.new(@server, @port)
        end
      else
        @sock=TCPSocket.new(@server, @port)
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

    def byterate
      return "#{@bytes_per}/#{@seconds_per}"
    end

    def byterate=(newrate)
      @qmutex.synchronize do
        setbyterate(newrate)
      end
    end

    def run_throttle(more=0)
      now = Time.new
      if @throttle_bytes > 0
        # If we ever reach the limit, we halve the actual allowed byterate
        # until we manage to reset the throttle.
        if @throttle_bytes >= @bytes_per
          @throttle_div = 0.5
        end
        delta = ((now - @last_throttle)*@throttle_div*@bytes_per/@seconds_per).floor
        if delta > 0
          @throttle_bytes -= delta
          @throttle_bytes = 0 if @throttle_bytes < 0
          @last_throttle = now
        end
      else
        @throttle_div = 1
      end
      @throttle_bytes += more
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

    # get the next line from the server (blocks)
    def gets
      if @sock.nil?
        warning "socket get attempted while closed"
        return nil
      end
      begin
        reply = @sock.gets
        @lines_received += 1
        reply.strip! if reply
        debug "RECV: #{reply.inspect}"
        return reply
      rescue => e
        warning "socket get failed: #{e.inspect}"
        debug e.backtrace.join("\n")
        return nil
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
            # reset burst counter after @sendq_delay has passed
            debug "resetting @burst"
            @burst = 0
          elsif (@burst >= @sendq_burst)
            # nope. can't send anything, come back to us next tick...
            debug "can't send yet"
            @timer.start
            return
          end
          debug "can send #{@sendq_burst - @burst} lines, there are #{@sendq.length} to send"
          (@sendq_burst - @burst).times do
            break if @sendq.empty?
            mess = @sendq.next
            if @throttle_bytes == 0 or mess.length+@throttle_bytes < @bytes_per
              debug "flood protection: sending message of length #{mess.length}"
              debug "(byterate: #{byterate}, throttle bytes: #{@throttle_bytes})"
              puts_critical(@sendq.shift)
            else
              debug "flood protection: throttling message of length #{mess.length}"
              debug "(byterate: #{byterate}, throttle bytes: #{@throttle_bytes})"
              run_throttle
              break
            end
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
      @sock.shutdown(how) unless @sock.nil?
      @sock = nil
      @burst = 0
    end

    private

    # same as puts, but expects to be called with a mutex held on @qmutex
    def puts_critical(message)
      # debug "in puts_critical"
      begin
        debug "SEND: #{message.inspect}"
        if @sock.nil?
          error "SEND attempted on closed socket"
        else
          @sock.send(message + "\n",0)
          @last_send = Time.new
          @lines_sent += 1
          @burst += 1
          run_throttle(message.length + 1)
        end
      rescue => e
        error "SEND failed: #{e.inspect}"
      end
    end

  end

end
