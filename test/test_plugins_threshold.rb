$:.unshift File.join(File.dirname(__FILE__), '../lib')

require 'test/unit'
require 'rbot/config'
require 'rbot/plugins'

require 'pp'

include Irc::Bot::Plugins

class TestRealBotModule < BotModule
  def initialize
  end
end

class MockModule < BotModule
  attr_reader :test_called_at
  attr_reader :test_arg_called_at
  attr_reader :connect_called_at
  attr_reader :test_arg_val

  def initialize(prio)
    @test_called_at = []
    @test_arg_called_at = []
    @connect_called_at = []
    @priority = prio
    @test_arg_val = nil
  end

  def test
    @test_called_at << Time.new
  end

  def test_arg a
    @test_arg_val = a
    @test_arg_called_at << Time.new
  end

  # an connect fast-delegate event
  def connect
    @connect_called_at << Time.new
  end

  def botmodule_class
    :CoreBotModule
  end
end

class PluginsPriorityTest < Test::Unit::TestCase
  @@manager = nil

  def setup
    @mock1 = MockModule.new(1)
    @mock2 = MockModule.new(2)
    @mock3 = MockModule.new(3)
    @mock4 = MockModule.new(4)
    @mock5 = MockModule.new(5)
      
    # This whole thing is a PITA because PluginManagerClass is a singleton
    unless @@manager
      @@manager = PluginManagerClass.instance

      # this is needed because debug is setup in the rbot starter
      def @@manager.debug(m); puts m; end
      def @@manager.error(m); puts m; end
      @@manager.instance_eval { alias real_sort_modules sort_modules }
      def @@manager.sort_modules
        @sort_call_count ||= 0
        @sort_call_count += 1
        real_sort_modules
      end
    end
    @@manager.instance_eval { @sort_call_count = nil }
    @@manager.mark_priorities_dirty

    # We add the modules to the lists in the wrong order 
    # on purpose to make sure the sort is working
    @@manager.plugins.clear
    @@manager.core_modules.clear
    @@manager.plugins << @mock1
    @@manager.plugins << @mock4
    @@manager.plugins << @mock3
    @@manager.plugins << @mock2
    @@manager.plugins << @mock5

    dlist = @@manager.instance_eval {@delegate_list['connect'.intern]}
    dlist.clear
    dlist << @mock1
    dlist << @mock4
    dlist << @mock3
    dlist << @mock2
    dlist << @mock5
  end
    
  def test_above
    @@manager.delegate_event('test', :above => 3)

    assert_equal 0, @mock1.test_called_at.size
    assert_equal 0, @mock2.test_called_at.size
    assert_equal 0, @mock3.test_called_at.size
    assert_equal 1, @mock4.test_called_at.size
    assert_equal 1, @mock5.test_called_at.size
  end
    
  def test_below
    @@manager.delegate_event('test', :below => 3)

    assert_equal 1, @mock1.test_called_at.size
    assert_equal 1, @mock2.test_called_at.size
    assert_equal 0, @mock3.test_called_at.size
    assert_equal 0, @mock4.test_called_at.size
    assert_equal 0, @mock5.test_called_at.size
  end

  def test_fast_delagate_above
    @@manager.delegate_event('connect', :above => 3)

    assert_equal 0, @mock1.connect_called_at.size
    assert_equal 0, @mock2.connect_called_at.size
    assert_equal 0, @mock3.connect_called_at.size
    assert_equal 1, @mock4.connect_called_at.size
    assert_equal 1, @mock5.connect_called_at.size
  end

  def test_fast_delagate_above
    @@manager.delegate_event('connect', :below => 3)

    assert_equal 1, @mock1.connect_called_at.size
    assert_equal 1, @mock2.connect_called_at.size
    assert_equal 0, @mock3.connect_called_at.size
    assert_equal 0, @mock4.connect_called_at.size
    assert_equal 0, @mock5.connect_called_at.size
  end

  def test_call_with_args
    @@manager.delegate_event('test_arg', :above => 3, :args => [1])

    assert_equal 0, @mock3.test_arg_called_at.size
    assert_equal 1, @mock4.test_arg_called_at.size
    assert_equal 1, @mock4.test_arg_val
  end
end

