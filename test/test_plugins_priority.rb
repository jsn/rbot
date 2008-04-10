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
  attr_reader :connect_called_at

  def initialize(prio)
    @test_called_at = []
    @connect_called_at = []
    @priority = prio
  end

  def test
    @test_called_at << Time.new
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
    
  def test_default_priority
    plugin = TestRealBotModule.new
    assert_equal 1, plugin.priority
  end

  def test_sort_called
    @@manager.delegate('test')

    assert @@manager.instance_eval { @sort_call_count }
  end

  def test_sort_called_once
    @@manager.delegate('test')
    @@manager.delegate('test')
    @@manager.delegate('test')
    @@manager.delegate('test')

    assert_equal 1, @@manager.instance_eval { @sort_call_count }
  end

  def test_sorted
    plugins = @@manager.plugins
    assert_equal @mock1, plugins[0]
    assert_equal @mock4, plugins[1]
    assert_equal @mock3, plugins[2]
    assert_equal @mock2, plugins[3]
    assert_equal @mock5, plugins[4]

    @@manager.sort_modules
    plugins = @@manager.instance_eval { @sorted_modules }

    assert_equal @mock1, plugins[0]
    assert_equal @mock2, plugins[1]
    assert_equal @mock3, plugins[2]
    assert_equal @mock4, plugins[3]
    assert_equal @mock5, plugins[4]
  end

  def test_fast_delegate_sort
    list = @@manager.instance_eval {@delegate_list['connect'.intern]}
    assert_equal @mock1, list[0]
    assert_equal @mock4, list[1]
    assert_equal @mock3, list[2]
    assert_equal @mock2, list[3]
    assert_equal @mock5, list[4]

    @@manager.sort_modules
    assert_equal @mock1, list[0]
    assert_equal @mock2, list[1]
    assert_equal @mock3, list[2]
    assert_equal @mock4, list[3]
    assert_equal @mock5, list[4]
  end

  def test_slow_called_in_order
    @@manager.delegate('test')
    assert_equal 1, @mock1.test_called_at.size
    assert_equal 1, @mock2.test_called_at.size
    assert_equal 1, @mock3.test_called_at.size
    assert_equal 1, @mock4.test_called_at.size
    assert_equal 1, @mock5.test_called_at.size

    assert @mock1.test_called_at.first < @mock2.test_called_at.first
    assert @mock2.test_called_at.first < @mock3.test_called_at.first
    assert @mock3.test_called_at.first < @mock4.test_called_at.first
    assert @mock4.test_called_at.first < @mock5.test_called_at.first
  end

  def test_fast_called_in_order
    @@manager.delegate('connect')
    assert_equal 1, @mock1.connect_called_at.size
    assert_equal 1, @mock2.connect_called_at.size
    assert_equal 1, @mock3.connect_called_at.size
    assert_equal 1, @mock4.connect_called_at.size
    assert_equal 1, @mock5.connect_called_at.size

    assert @mock1.connect_called_at.first < @mock2.connect_called_at.first
    assert @mock2.connect_called_at.first < @mock3.connect_called_at.first
    assert @mock3.connect_called_at.first < @mock4.connect_called_at.first
    assert @mock4.connect_called_at.first < @mock5.connect_called_at.first
  end

  def test_add_botmodule
    @@manager.sort_modules
    mock_n1 = MockModule.new(-1)
    @@manager.add_botmodule mock_n1
    @@manager.delegate('test')
    assert mock_n1.test_called_at.first < @mock1.test_called_at.first
  end
end

