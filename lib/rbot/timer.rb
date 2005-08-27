module Timer

  # timer event, something to do and when/how often to do it
  class Action
    
    # when this action is due next (updated by tick())
    attr_reader :in
    
    # is this action blocked? if so it won't be run
    attr_accessor :blocked

    # period:: how often (seconds) to run the action
    # data::   optional data to pass to the proc
    # once::   optional, if true, this action will be run once then removed
    # func::   associate a block to be called to perform the action
    # 
    # create a new action
    def initialize(period, data=nil, once=false, &func)
      @blocked = false
      @period = period
      @in = period
      @func = func
      @data = data
      @once = once
      @last_tick = Time.new
    end

    def tick
      diff = Time.new - @last_tick
      @in -= diff
      @last_tick = Time.new
    end

    def inspect 
      "#<#{self.class}:#{@period}s:#{@once ? 'once' : 'repeat'}>"
    end

    def due?
      @in <= 0
    end

    # run the action by calling its proc
    def run
      @in += @period
      # really short duration timers can overrun and leave @in negative,
      # for these we set @in to @period
      @in = @period if @in <= 0
      if(@data)
        @func.call(@data)
      else
        @func.call
      end
      return @once
    end
  end
  
  # timer handler, manage multiple Action objects, calling them when required.
  # The timer must be ticked by whatever controls it, i.e. regular calls to
  # tick() at whatever granularity suits your application's needs.
  # 
  # Alternatively you can call run(), and the timer will spawn a thread and
  # tick itself, intelligently shutting down the thread if there are no
  # pending actions.
  class Timer
    def initialize(granularity = 0.1)
      @granularity = granularity
      @timers = Hash.new
      @handle = 0
      @lasttime = 0
      @should_be_running = false
      @thread = false
      @next_action_time = 0
    end
    
    # period:: how often (seconds) to run the action
    # data::   optional data to pass to the action's proc
    # func::   associate a block with add() to perform the action
    # 
    # add an action to the timer
    def add(period, data=nil, &func)
      debug "adding timer, period #{period}"
      @handle += 1
      @timers[@handle] = Action.new(period, data, &func)
      start_on_add
      return @handle
    end

    # period:: how long (seconds) until the action is run
    # data::   optional data to pass to the action's proc
    # func::   associate a block with add() to perform the action
    # 
    # add an action to the timer which will be run just once, after +period+
    def add_once(period, data=nil, &func)
      debug "adding one-off timer, period #{period}"
      @handle += 1
      @timers[@handle] = Action.new(period, data, true, &func)
      start_on_add
      return @handle
    end

    # remove action with handle +handle+ from the timer
    def remove(handle)
      @timers.delete(handle)
    end
    
    # block action with handle +handle+
    def block(handle)
      @timers[handle].blocked = true
    end

    # unblock action with handle +handle+
    def unblock(handle)
      @timers[handle].blocked = false
    end

    # you can call this when you know you're idle, or you can split off a
    # thread and call the run() method to do it for you.
    def tick 
      if(@lasttime == 0)
        # don't do anything on the first tick
        @lasttime = Time.now
        return
      end
      @next_action_time = 0
      diff = (Time.now - @lasttime).to_f
      @lasttime = Time.now
      @timers.each { |key,timer|
        timer.tick
        next if timer.blocked
        if(timer.due?)
          if(timer.run)
            # run once
            @timers.delete(key)
          end
        end
        if @next_action_time == 0 || timer.in < @next_action_time
          @next_action_time = timer.in
        end
      }
      #debug "ticked. now #{@timers.length} timers remain"
      #debug "next timer due at #{@next_action_time}"
    end

    # for backwards compat - this is a bit primitive
    def run(granularity=0.1)
      while(true)
        sleep(granularity)
        tick
      end
    end

    def running?
      @thread && @thread.alive?
    end

    # return the number of seconds until the next action is due, or 0 if
    # none are outstanding - will only be accurate immediately after a
    # tick()
    def next_action_time
      @next_action_time
    end

    # start the timer, it spawns a thread to tick the timer, intelligently
    # shutting down if no events remain and starting again when needed.
    def start
      return if running?
      @should_be_running = true
      start_thread unless @timers.empty?
    end

    # stop the timer from ticking
    def stop
      @should_be_running = false
      stop_thread
    end
    
    private
    
    def start_on_add
      if running?
        stop_thread
        start_thread
      elsif @should_be_running
        start_thread
      end
    end
    
    def stop_thread
      return unless running?
      @thread.kill
    end
    
    def start_thread
      return if running?
      @thread = Thread.new do
        while(true)
          tick
          exit if @timers.empty?
          sleep(@next_action_time)
        end
      end
    end

  end
end
