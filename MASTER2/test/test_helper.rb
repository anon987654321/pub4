# frozen_string_literal: true

if ENV["COVERAGE"]
  require "simplecov"
  SimpleCov.start do
    add_filter "/test/"
    add_filter "/vendor/"
    add_group "Core", "lib"
    add_group "Executor", "lib/executor"
    add_group "LLM", "lib/llm"
    add_group "Stages", "lib/stages.rb"
    add_group "Pipeline", "lib/pipeline"
    minimum_coverage 50  # Start low, ratchet up over time
    minimum_coverage_by_file 20
  end
end

require "minitest/autorun"
require "tmpdir"
require "timeout"
require_relative "../lib/master"

# Global test timeout — prevents tests from hanging indefinitely
Minitest::Test.class_eval do
  alias_method :run_without_timeout, :run
  def run(*args)
    Timeout.timeout(30) { run_without_timeout(*args) }
  rescue Timeout::Error
    failures << Minitest::UnexpectedError.new(Timeout::Error.new("Test timed out after 30s"))
    self
  end
end

# Shared test setup
module TestHelper
  def setup_db
    @test_db_dir = Dir.mktmpdir
    MASTER::DB.setup(path: @test_db_dir)
  end

  def teardown_db
    FileUtils.rm_rf(@test_db_dir) if @test_db_dir && Dir.exist?(@test_db_dir)
  end
end

require_relative "support/llm_stubs"

class Minitest::Test
  include TestHelper
  include LLMStubs
end

# Skip guard for integration tests needing API key
LLM_AVAILABLE = ENV.key?("OPENROUTER_API_KEY")

def skip_unless_llm(msg = "Requires OPENROUTER_API_KEY")
  skip msg unless LLM_AVAILABLE
end
