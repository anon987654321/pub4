# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../../lib/converge"

class ConvergeEngineSpec < Minitest::Test
  def with_home
    Dir.mktmpdir do |dir|
      old_home = ENV["HOME"]
      ENV["HOME"] = dir
      yield
    ensure
      ENV["HOME"] = old_home
    end
  end

  def test_runs_convergence
    with_home do
      engine = Converge::Engine.new(File.expand_path("../../data/converge_rules.yml", __dir__))
      result = engine.run(code: "", reply_text: "plain reply")
      assert result.key?(:violations)
    end
  end


  def test_max_iterations_can_be_configured_per_run
    with_home do
      engine = Converge::Engine.new(File.expand_path("../../data/converge_rules.yml", __dir__))
      events = []
      engine.subscribe { |event| events << event }
      result = engine.run(code: "", reply_text: "plain reply", max_iterations: 1)

      assert_equal 1, result[:execution_depth]
      assert events.any? { |event| event[:type] == :"convergence:max_iterations" }
    end
  end

  def test_emits_events_to_subscribers
    with_home do
      engine = Converge::Engine.new(File.expand_path("../../data/converge_rules.yml", __dir__))
      events = []
      engine.subscribe { |event| events << event }
      engine.run(code: "")
      refute_empty events
    end
  end
end
