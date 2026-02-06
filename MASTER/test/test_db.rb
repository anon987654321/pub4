#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'fileutils'
require_relative '../lib/db'

class TestDB < Minitest::Test
  def setup
    # Use a test database
    @original_db = MASTER::DB::DB_PATH
    MASTER::DB.const_set(:DB_PATH, '/tmp/test_master.db')
    FileUtils.rm_f('/tmp/test_master.db')
    MASTER::DB.init!
  end
  
  def teardown
    MASTER::DB.connection.close if MASTER::DB.instance_variable_get(:@db)
    FileUtils.rm_f('/tmp/test_master.db')
    MASTER::DB.instance_variable_set(:@db, nil)
  end
  
  def test_init_creates_tables
    tables = MASTER::DB.connection.execute("SELECT name FROM sqlite_master WHERE type='table'")
    table_names = tables.map { |t| t['name'] }
    
    assert_includes table_names, 'principles'
    assert_includes table_names, 'personas'
    assert_includes table_names, 'memory'
    assert_includes table_names, 'costs'
    assert_includes table_names, 'config'
  end
  
  def test_upsert_principle
    MASTER::DB.upsert_principle(
      name: 'TEST',
      text: 'Test principle',
      protection_level: 'flexible'
    )
    
    principle = MASTER::DB.principle('TEST')
    assert_equal 'TEST', principle['name']
    assert_equal 'Test principle', principle['text']
    assert_equal 'flexible', principle['protection_level']
  end
  
  def test_track_cost
    MASTER::DB.track_cost(
      model: 'deepseek-chat',
      tier: 'default',
      tokens_in: 100,
      tokens_out: 200,
      cost: 0.003
    )
    
    spend = MASTER::DB.daily_spend
    assert_in_delta 0.003, spend, 0.001
  end
  
  def test_store_and_recall_memory
    id = MASTER::DB.store_memory(
      content: 'Test memory',
      context: 'test'
    )
    
    assert id > 0
    
    memories = MASTER::DB.recall_memories(context: 'test')
    assert_equal 1, memories.length
    assert_equal 'Test memory', memories[0]['content']
  end
  
  def test_config
    MASTER::DB.set_config('test_key', 'test_value')
    
    value = MASTER::DB.config('test_key')
    assert_equal 'test_value', value
    
    default = MASTER::DB.config('nonexistent', 'default')
    assert_equal 'default', default
  end
  
  def test_circuit_breaker
    model = 'test-model'
    
    # Initial state
    state = MASTER::DB.circuit_state(model)
    assert_equal 'closed', state['state']
    
    # Record failures
    MASTER::DB.record_failure(model)
    MASTER::DB.record_failure(model)
    MASTER::DB.record_failure(model)
    
    state = MASTER::DB.circuit_state(model)
    assert_equal 'open', state['state']
    
    # Record success
    MASTER::DB.record_success(model)
    state = MASTER::DB.circuit_state(model)
    assert_equal 'closed', state['state']
  end
end
