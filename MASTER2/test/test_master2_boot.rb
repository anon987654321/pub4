# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/master"

class TestMaster2Boot < Minitest::Test
  def test_master_module_defined
    assert defined?(MASTER)
    assert_equal "1.0.0", MASTER::VERSION
  end

  def test_core_classes_loaded
    assert defined?(MASTER::Result)
    assert defined?(MASTER::Pipeline)
    assert defined?(MASTER::Executor)
    assert defined?(MASTER::Stages)
    assert defined?(MASTER::LLM)
    assert defined?(MASTER::DB)
    assert defined?(MASTER::CircuitBreaker)
  end

  def test_stages_loaded_correctly
    assert defined?(MASTER::Stages::Intake)
    assert defined?(MASTER::Stages::Compress)
    assert defined?(MASTER::Stages::Guard)
    assert defined?(MASTER::Stages::Route)
  end

  def test_executor_depends_on_stages
    # Verify that Executor's DANGEROUS_PATTERNS references Stages::Guard
    assert_equal MASTER::Stages::Guard::DANGEROUS_PATTERNS, MASTER::Executor::DANGEROUS_PATTERNS
  end

  def test_result_monad_works
    ok = MASTER::Result.ok("value")
    assert ok.ok?
    refute ok.err?
    assert_equal "value", ok.value

    err = MASTER::Result.err("error")
    refute err.ok?
    assert err.err?
    assert_equal "error", err.error
  end

  def test_pipeline_initializes
    pipeline = MASTER::Pipeline.new
    assert_kind_of MASTER::Pipeline, pipeline
  end

  def test_executor_initializes
    executor = MASTER::Executor.new
    assert_kind_of MASTER::Executor, executor
  end

  def test_db_setup
    # Ensure DB can be set up without errors
    require "tmpdir"
    Dir.mktmpdir do |tmpdir|
      MASTER::DB.setup(path: tmpdir)
      assert_equal tmpdir, MASTER::DB.root
    end
  end

  def test_logging_module_available
    assert defined?(MASTER::Logging)
    assert MASTER::Logging.respond_to?(:info)
    assert MASTER::Logging.respond_to?(:warn)
    assert MASTER::Logging.respond_to?(:error)
  end

  def test_constitution_module_loaded
    assert defined?(MASTER::Constitution)
  end

  def test_speech_module_loaded
    assert defined?(MASTER::Speech)
    assert MASTER::Speech.respond_to?(:chatter)
  end

  def test_server_class_loaded
    skip "Server might not be available" unless defined?(MASTER::Server)
    # Server is loaded, verify it has expected methods
    assert MASTER::Server.respond_to?(:new)
  end
end
