module Timer

  # timer event, something to do and when/how often to do it
  class Action
    
    # when this action is due next (updated by tick())
    attr_accessor :in
    
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
    end

    # run the action by calling its proc
    def run
      @in += @period
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
  # Alternatively you can call run(), and the timer will tick itself, but this
  # blocks so you gotta do it in a thread (remember ruby's threads block on
  # syscalls so that can suck).
  class Timer
    def initialize
      @timers = Array.new
      @handle = 0
      @lasttime = 0
    end
    
    # period:: how often (seconds) to run the action
    # data::   optional data to pass to the action's proc
    # func::   associate a block with add() to perform the action
    # 
    # add an action to the timer
    def add(period, data=nil, &func)
      @handle += 1
      @timers[@handle] = Action.new(period, data, &func)
      return @handle
    end

    # period:: how often (seconds) to run the action
    # data::   optional data to pass to the action's proc
    # func::   associate a block with add() to perform the action
    # 
    # add an action to the timer which will be run just once, after +period+
    def add_once(period, data=nil, &func)
      @handle += 1
      @timers[@handle] = Action.new(period, data, true, &func)
      return @handle
    end

    # remove action with handle +handle+ from the timer
    def remove(handle)
      @timers.delete_at(handle)
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
      if(@lasttime != 0)
        diff = (Time.now - @lasttime).to_f
        @lasttime = Time.now
        @timers.compact.each { |timer|
          timer.in = timer.in - diff
        }
        @timers.compact.each { |timer|
          if (!timer.blocked)
            if(timer.in <= 0)
              if(timer.run)
                # run once
                @timers.delete(timer)
              end
            end
          end
        }
      else
        # don't do anything on the first tick
        @lasttime = Time.now
      end
    end

    # the timer will tick() itself. this blocks, so run it in a thread, and
    # watch out for blocking syscalls
    def run(granularity=0.1)
      while(true)
        sleep(granularity)
        tick
      end
    end
  end
end
