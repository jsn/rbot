#-- vim:sw=2:et
#++
#
# :title: IRC Socket
#
# This module implements the IRC socket interface, including IRC message
# penalty computation and the message queue system

require 'monitor'

class ::String
  # Calculate the penalty which will be assigned to this message
  # by the IRCd
  def irc_send_penalty
    # According to eggdrop, the initial penalty is
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
      args = pars.split
      if args.length > 0
        penalty += args.inject(0){ |sum,x| sum += ((x.length > 4) ? 3 : 5) }
      else
        penalty += 10
      end
    when :PART
      penalty += 4
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
      self.extend(MonitorMixin)
      @non_empty = self.new_cond
    end

    def clear
      self.synchronize do
        @rings.each { |r| r.clear }
        @last_ring = 0
      end
    end

    def push(mess, chan=nil, cring=0)
      ring = cring
      self.synchronize do
        if ring == 0
          warning "message #{mess} at ring 0 has channel #{chan}: channel will be ignored" if !chan.nil?
          @rings[0] << mess
        else
          error "message #{mess} at ring #{ring} must have a channel" if chan.nil?
          @rings[ring].push mess, chan
        end
        @non_empty.signal
      end
    end

    def shift(tmout = nil)
      self.synchronize do
        @non_empty.wait(tmout) if self.empty?
        return unsafe_shift
      end
    end

    protected

    def empty?
      !@rings.find { |r| !r.empty? }
    end

    def length
      @rings.inject(0) { |s, r| s + r.size }
    end
    alias :size :length

    def unsafe_shift
      if !@rings[0].empty?
        return @rings[0].shift
      end
      (@rings.size - 1).times do
        @last_ring = (@last_ring % (@rings.size - 1)) + 1
        return @rings[@last_ring].shift unless @rings[@last_ring].empty?
      end
      warning "trying to access an empty message queue"
      return nil
    end

  end

  # wrapped TCPSocket for communication with the server.
  # emulates a subset of TCPSocket functionality
  class Socket

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

    # an optional filter object. we call @filter.in(data) for
    # all incoming data and @filter.out(data) for all outgoing data
    attr_reader :filter

    # normalized uri of the current server
    attr_reader :server_uri

    # penalty multiplier (percent)
    attr_accessor :penalty_pct

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
    # create a new Irc::Socket
    def initialize(server_list, host, opts={})
      @server_list = server_list.dup
      @server_uri = nil
      @conn_count = 0
      @host = host
      @sock = nil
      @filter = IdentityFilter.new
      @spooler = false
      @lines_sent = 0
      @lines_received = 0
      @ssl = opts[:ssl]
      @ssl_verify = opts[:ssl_verify]
      @ssl_ca_file = opts[:ssl_ca_file]
      @ssl_ca_path = opts[:ssl_ca_path]
      @penalty_pct = opts[:penalty_pct] || 100
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

      # if the host is a bracketed (IPv6) address, strip the brackets
      # since Ruby doesn't like them in the Socket host parameter
      # FIXME it would be safer to have it check for a valid
      # IPv6 bracketed address rather than just stripping the brackets
      srv_host = @server_uri.host
      if srv_host.match(/\A\[(.*)\]\z/)
        srv_host = $1
      end

      if(@host)
        begin
          sock=TCPSocket.new(srv_host, @server_uri.port, @host)
        rescue ArgumentError => e
          error "Your version of ruby does not support binding to a "
          error "specific local address, please upgrade if you wish "
          error "to use HOST = foo"
          error "(this option has been disabled in order to continue)"
          sock=TCPSocket.new(srv_host, @server_uri.port)
        end
      else
        sock=TCPSocket.new(srv_host, @server_uri.port)
      end
      if(@ssl)
        require 'openssl'
        ssl_context = OpenSSL::SSL::SSLContext.new()
        if @ssl_verify
          ssl_context.ca_file = @ssl_ca_file if @ssl_ca_file and not @ssl_ca_file.empty?
          ssl_context.ca_path = @ssl_ca_path if @ssl_ca_path and not @ssl_ca_path.empty?
          ssl_context.verify_mode = OpenSSL::SSL::VERIFY_PEER 
        else
          ssl_context.verify_mode = OpenSSL::SSL::VERIFY_NONE
        end
        sock = OpenSSL::SSL::SSLSocket.new(sock, ssl_context)
        sock.sync_close = true
        sock.connect
      end
      @sock = sock
      @last_send = Time.new
      @flood_send = Time.new
      @burst = 0
      @sock.extend(MonitorMixin)
      @sendq = MessageQueue.new
      @qthread = Thread.new { writer_loop }
    end

    # used to send lines to the remote IRCd by skipping the queue
    # message: IRC message to send
    # it should only be used for stuff that *must not* be queued,
    # i.e. the initial PASS, NICK and USER command
    # or the final QUIT message
    def emergency_puts(message, penalty = false)
      @sock.synchronize do
        # debug "In puts - got @sock"
        puts_critical(message, penalty)
      end
    end

    def handle_socket_error(string, e)
      error "#{string} failed: #{e.pretty_inspect}"
      # We assume that an error means that there are connection
      # problems and that we should reconnect, so we
      shutdown
      raise SocketError.new(e.inspect)
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
      rescue Exception => e
        handle_socket_error(:RECV, e)
      end
    end

    def queue(msg, chan=nil, ring=0)
      @sendq.push msg, chan, ring
    end

    def clearq
      @sendq.clear
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
      @qthread.kill
      @qthread = nil
      begin
        @sock.close
      rescue Exception => e
        error "error while shutting down: #{e.pretty_inspect}"
      end
      @sock = nil
      @server_uri = nil
      @sendq.clear
    end

    private

    def writer_loop
      loop do
        begin
          now = Time.now
          flood_delay = @flood_send - MAX_IRC_SEND_PENALTY - now
          delay = [flood_delay, 0].max
          if delay > 0
            debug "sleep(#{delay}) # (f: #{flood_delay})"
            sleep(delay)
          end
          msg = @sendq.shift
          debug "got #{msg.inspect} from queue, sending"
          emergency_puts(msg, true)
        rescue Exception => e
          error "Spooling failed: #{e.pretty_inspect}"
          debug e.backtrace.join("\n")
          raise e
        end
      end
    end

    # same as puts, but expects to be called with a lock held on @sock
    def puts_critical(message, penalty=false)
      # debug "in puts_critical"
      begin
        debug "SEND: #{message.inspect}"
        if @sock.nil?
          error "SEND attempted on closed socket"
        else
          # we use Socket#syswrite() instead of Socket#puts() because
          # the latter is racy and can cause double message output in
          # some circumstances
          actual = @filter.out(message) + "\n"
          now = Time.new
          @sock.syswrite actual
          @last_send = now
          @flood_send = now if @flood_send < now
          @flood_send += message.irc_send_penalty*@penalty_pct/100.0 if penalty
          @lines_sent += 1
        end
      rescue Exception => e
        handle_socket_error(:SEND, e)
      end
    end

  end

end
