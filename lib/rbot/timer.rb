# changes:
#  1. Timer::Timer ---> Timer
#  2. timer id is now the object_id of the action
#  3. Timer resolution removed, we're always arbitrary precision now
#  4. I don't see any obvious races [not that i did see any in old impl, though]
#  5. We're tickless now, so no need to jerk start/stop
#  6. We should be pretty fast now, wrt old impl
#  7. reschedule/remove/block now accept nil as an action id (meaning "current")
#  8. repeatability is ignored for 0-period repeatable timers
#  9. configure() method superceeds reschedule() [the latter stays as compat]

require 'thread'
require 'monitor'

# Timer handler, manage multiple Action objects, calling them when required.
# When the Timer is constructed, a new Thread is created to manage timed
# delays and run Actions.
#
# XXX: there is no way to stop the timer currently. I'm keeping it this way
# to weed out old Timer implementation legacy in rbot code. -jsn.
class Timer

  # class representing individual timed action
  class Action

    # Time when the Action should be called next
    attr_accessor :next

    # Options are:
    # start::    Time when the Action should be run for the first time.
    #            Repeatable Actions will be repeated after that, see
    #            :period. One-time Actions will not (obviously)
    #            Default: Time.now + :period
    # period::   How often repeatable Action should be run, in seconds.
    #            Default: 1
    # blocked::  if true, Action starts as blocked (i.e. will stay dormant
    #            until unblocked)
    # args::     Arguments to pass to the Action callback. Default: []
    # repeat::   Should the Action be called repeatedly? Default: false
    # code::     You can specify the Action body using &block, *or* using
    #            this option.

    def initialize(options = {}, &block)
      opts = {
        :period => 1,
        :blocked => false,
        :args => [],
        :repeat => false
      }.merge(options)

      @block = nil
      debug("adding timer #{self} :period => #{opts[:period]}, :repeat => #{opts[:repeat].inspect}")
      self.configure(opts, &block)
      debug("added #{self}")
    end

    # Provides for on-the-fly reconfiguration of the Actions
    # Accept the same arguments as the constructor
    def configure(opts = {}, &block)
      @period = opts[:period] if opts.include? :period
      @blocked = opts[:blocked] if opts.include? :blocked
      @repeat = opts[:repeat] if opts.include? :repeat

      if block_given?
        @block = block
      elsif opts[:code]
        @block = opts[:code]
      end

      raise 'huh?? blockless action?' unless @block
      if opts.include? :args
        @args = Array === opts[:args] ? opts[:args] : [opts[:args]]
      end

      if opts[:start] and (Time === opts[:start])
        self.next = opts[:start]
      else
        self.next = Time.now + (opts[:start] || @period)
      end
    end

    # modify the Action period
    def reschedule(period, &block)
      self.configure(:period => period, &block)
    end

    # blocks an Action, so it won't be run
    def block
      @blocked = true
    end

    # unblocks a blocked Action
    def unblock
      @blocked = false
    end

    def blocked?
      @blocked
    end

    # calls the Action callback, resets .next to the Time of the next call,
    # if the Action is repeatable.
    def run(now = Time.now)
      raise 'inappropriate time to run()' unless self.next && self.next <= now
      self.next = nil
      begin
        @block.call(*@args)
      rescue Exception => e
        error "Timer action #{self.inspect}: block #{@block.inspect} failed!"
        error e.pretty_inspect
        debug e.backtrace.join("\n")
      end

      if @repeat && @period > 0
        self.next = now + @period
      end

      return self.next
    end
  end

  # creates a new Timer and starts it.
  def initialize
    self.extend(MonitorMixin)
    @tick = self.new_cond
    @thread = nil
    @actions = Hash.new
    @current = nil
    self.start
  end

  # Creates and installs a new Action, repeatable by default.
  # _period_:: Action period
  # _opts_::   options for Action#new, see there
  # _block_::  Action callback code
  #
  # Returns the id of the created Action
  def add(period, opts = {}, &block)
    a = Action.new({:repeat => true, :period => period}.merge(opts), &block)
    self.synchronize do
      @actions[a.object_id] = a
      @tick.signal
    end
    return a.object_id
  end

  # Creates and installs a new Action, one-time by default.
  # _period_:: Action delay
  # _opts_::   options for Action#new, see there
  # _block_::  Action callback code
  #
  # Returns the id of the created Action
  def add_once(period, opts = {}, &block)
    self.add(period, {:repeat => false}.merge(opts), &block)
  end

  # blocks an existing Action
  # _aid_:: Action id, obtained previously from add() or add_once()
  def block(aid)
    debug "blocking #{aid}"
    self.synchronize { self[aid].block }
  end

  # unblocks an existing blocked Action
  # _aid_:: Action id, obtained previously from add() or add_once()
  def unblock(aid)
    debug "unblocking #{aid}"
    self.synchronize do
      self[aid].unblock
      @tick.signal
    end
  end

  # removes an existing blocked Action
  # _aid_:: Action id, obtained previously from add() or add_once()
  def remove(aid)
    self.synchronize do
      @actions.delete(aid) # or raise "nonexistent action #{aid}"
    end
  end

  alias :delete :remove

  # Provides for on-the-fly reconfiguration of Actions
  # _aid_::   Action id, obtained previously from add() or add_once()
  # _opts_::  see Action#new
  # _block_:: (optional) new Action callback code
  def configure(aid, opts = {}, &block)
    self.synchronize do
      self[aid].configure(opts, &block)
      @tick.signal
    end
  end

  # changes Action period
  # _aid_:: Action id
  # _period_:: new period
  # _block_:: (optional) new Action callback code
  def reschedule(aid, period, &block)
    self.configure(aid, :period => period, &block)
  end

  def start
    raise 'already started' if @thread
    @stopping = false
    debug "starting timer #{self}"
    @thread = Thread.new do
      loop do
        tmout = self.run_actions
        break if tmout and tmout < 0
        self.synchronize { @tick.wait(tmout) }
      end
    end
  end

  def stop
    unless @thread
      warning 'trying to stop already stopped timer'
      return
    end
    debug "stopping timer #{self}..."
    @stopping = true
    self.synchronize { @tick.signal }
    @thread.join(60) or @thread.kill
    debug "timer #{self} stopped"
    @thread = nil
  end

  protected

  def [](aid)
    aid ||= @current
    raise "no current action" unless aid
    raise "nonexistent action #{aid}" unless @actions.include? aid
    @actions[aid]
  end

  def run_actions(now = Time.now)
    @actions.keys.each do |k|
      return -1 if @stopping
      a = @actions[k] or next
      next if a.blocked? || a.next > now

      begin
        @current = k
        a.run(now)
      ensure
        @current = nil
      end

      @actions.delete k unless a.next
    end

    nxt = @actions.values.find_all { |v| !v.blocked? }.map{ |v| v.next }.min

    if nxt
      delta = nxt - now
      delta = 0 if delta < 0
      return delta
    else
      return nil
    end
  end

end
