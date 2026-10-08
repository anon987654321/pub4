# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/fix/fix_loop"

class TestFixLoopObservability < Minitest::Test
  EventBus = Struct.new(:events) do
    def publish(name, payload = {})
      events << [name.to_s, payload]
    end
  end

  Collector = Struct.new(:candidate_count, :skipped, :files) do
    def collect(_target) = files
  end

  Discipline = Struct.new(:error) do
    def begin_run(_files)
      raise error
    end
  end

  def test_begin_run_crash_is_distinct_from_corpus_findings
    bus = EventBus.new([])
    error = FloatDomainError.new("Infinity can't be coerced into Integer")
    loop = Master::Fix::FixLoop.allocate
    loop.instance_variable_set(:@bus, bus)
    loop.instance_variable_set(:@file_collector, Collector.new(1, 0, [File.join(Master::ROOT, "data", "laws.yml")]))
    loop.instance_variable_set(:@convergence_discipline, Discipline.new(error))
    loop.instance_variable_set(:@run_journal, nil)

    output, = capture_io do
      result = loop.send(
        :run_unlocked,
        Master::ROOT,
        max_passes: 1,
        budget_seconds: 30,
        incremental: false,
        requested: true,
      )
      @result = result
    end

    crash = bus.events.fetch(0)

    assert_equal "fix_loop:crash", crash.fetch(0)
    assert_equal "FloatDomainError", crash.fetch(1).fetch(:error_class)
    assert_equal "begin_run", crash.fetch(1).fetch(:phase)
    assert_equal :crash, @result.category
    assert_match(/crash FloatDomainError @ begin_run/, output)
    refute_match(/corpus .*FloatDomainError/i, output)
  end
end
