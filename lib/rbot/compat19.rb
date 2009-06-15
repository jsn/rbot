#-- vim:sw=2:et
#++
#
# :title: ruby 1.9 compatibility (monkey)patches

require 'timeout'
require "thread"

class ConditionVariable

  def wait(mutex, timeout=nil)
    begin
      # TODO: mutex should not be used
      @waiters_mutex.synchronize do
        @waiters.push(Thread.current)
      end
      if timeout
        elapsed = mutex.sleep timeout if timeout > 0.0
        unless timeout > 0.0 and elapsed < timeout
          t = @waiters_mutex.synchronize { @waiters.delete Thread.current }
          signal unless t # if we got notified, pass it along
          raise TimeoutError, "wait timed out"
        end
      else
        mutex.sleep
      end
    end
    nil
  end

end

require 'monitor'

module MonitorMixin

  class ConditionVariable

    def wait(timeout = nil)
      #if timeout
      #  raise NotImplementedError, "timeout is not implemented yet"
      #end
      @monitor.__send__(:mon_check_owner)
      count = @monitor.__send__(:mon_exit_for_cond)
      begin
        @cond.wait(@monitor.instance_variable_get("@mon_mutex"), timeout)
        return true
      ensure
        @monitor.__send__(:mon_enter_for_cond, count)
      end
    end

    def signal
      @monitor.__send__(:mon_check_owner)
      @cond.signal
    end

    def broadcast
      @monitor.__send__(:mon_check_owner)
      @cond.broadcast
    end

  end  # ConditionVariable

  def self.extend_object(obj)
    super(obj)
    obj.__send__(:mon_initialize)
  end

end # MonitorMixin
