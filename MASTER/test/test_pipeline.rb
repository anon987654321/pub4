# frozen_string_literal: true

require "minitest/autorun"
require "sqlite3"
require_relative "../lib/result"
require_relative "../lib/db"
require_relative "../lib/circuit"
require_relative "../lib/budget"
require_relative "../lib/typography"
require_relative "../lib/pipeline"

class TestPipeline < Minitest::Test
  def setup
    # Setup in-memory DB
    @db_conn = SQLite3::Database.new(":memory:")
    @db_conn.results_as_hash = true
    
    @original_db = MASTER::DB.instance_variable_get(:@connection)
    MASTER::DB.instance_variable_set(:@connection, @db_conn)
    MASTER::DB.initialize_schema
  end

  def teardown
    MASTER::DB.instance_variable_set(:@connection, @original_db)
  end

  def test_pipeline_chains_stages
    # Use only intake and guard stages for simple test
    pipeline = MASTER::Pipeline.new(stages: [:intake, :guard])
    result = pipeline.call({ text: "hello" })
    
    assert result.ok?
    assert_equal "hello", result.value[:text]
  end

  def test_pipeline_stops_on_error
    # Guard will block this
    pipeline = MASTER::Pipeline.new(stages: [:intake, :guard])
    result = pipeline.call({ text: "rm -rf /" })
    
    assert result.err?
  end

  def test_pipeline_passes_data_through_stages
    pipeline = MASTER::Pipeline.new(stages: [:intake, :guard])
    result = pipeline.call({ text: "safe command" })
    
    assert result.ok?
    assert_equal "safe command", result.value[:text]
  end

  def test_custom_stage_order
    pipeline = MASTER::Pipeline.new(stages: [:intake, :guard, :render])
    result = pipeline.call({ text: "test", response: "response text" })
    
    assert result.ok?
  end
end
