# frozen_string_literal: true

require "minitest/autorun"
require "master"

# The context budget adapts to the host so a ~1GB VPS compacts sooner and never
# feeds the OOM-killer. budget_for is the pure policy; these pin its edges.
class HostBudgetTest < Minitest::Test
  M = Master::Core::Memory

  def test_constrained_host_gets_the_small_budget
    assert_equal M::CONSTRAINED_BUDGET, M.budget_for(1024)
    assert_equal M::CONSTRAINED_BUDGET, M.budget_for(M::CONSTRAINED_MB)
  end

  def test_roomy_host_gets_the_generous_budget
    assert_equal M::GENEROUS_BUDGET, M.budget_for(M::CONSTRAINED_MB + 1)
    assert_equal M::GENEROUS_BUDGET, M.budget_for(16_384)
  end

  def test_unknown_memory_stays_generous
    assert_equal M::GENEROUS_BUDGET, M.budget_for(nil)
  end

  def test_default_memory_uses_a_positive_budget
    assert_operator M.new.instance_variable_get(:@budget), :>, 0
  end

  # The model saw "read(path)" and read the same file again; it sees the path,
  # and STATE lists what it has read.
  def test_an_action_is_recorded_by_its_subject
    memory = M.new
    memory.note(:goal, "explain logging")
    memory.record(Master::Core::Effect.read("lib/trace/logging.rb"), Master::Core::Observation.ok("x"))

    texts = memory.context.map(&:text)
    assert_includes texts, "read lib/trace/logging.rb"
    assert_match(/read: lib\/trace\/logging\.rb; evidence: 0\/\d+; done: allowed/, texts.last)
  end

  def test_a_repeated_read_of_an_unchanged_file_is_not_shown_again
    memory = M.new
    read = Master::Core::Effect.read("lib/x.rb")
    2.times { memory.record(read, Master::Core::Observation.ok("A = 1\n")) }

    observations = memory.context.select { |entry| entry.role == :obs }.map(&:text)
    assert_match(/A = 1/, observations.first)
    assert_match(/\AERR: lib\/x\.rb is unchanged/, observations.last)
    refute_match(/A = 1/, observations.last)
  end

  def test_the_same_action_after_it_failed_says_do_something_else
    memory = M.new
    ask = Master::Core::Effect.ask("what does it do?")
    2.times { memory.record(ask, Master::Core::Observation.no("no surface to ask")) }

    observations = memory.context.select { |entry| entry.role == :obs }.map(&:text)
    assert_equal "ERR: no surface to ask", observations.first
    assert_match(/just failed.*Do something else/, observations.last)
  end

  def test_compact_drops_oldest_acts_once_the_budget_is_exceeded
    memory = M.new(budget: 80, summarize: ->(dropped) { "SUM #{dropped.length}" })
    memory.note(:goal, "do the thing")
    12.times do |i|
      memory.record(
        Master::Core::Effect.exec(["echo", "act-#{i}-xxxxxxxx"]),
        Master::Core::Observation.no("obs-#{i}-xxxxxxxx"),
      )
    end

    ctx = memory.context
    # The goal is pinned and the STATE line closes every context; the budget
    # bounds the history between them.
    history = ctx[1...-1].map(&:text).join
    assert_operator history.length, :<=, 80 + 20, "compact left #{history.length} chars"
    assert ctx.any? { |e| e.text.start_with?("SUM") }, "oldest turns were not summarised"
    assert_equal "goal: do the thing", ctx.first.text, "compaction dropped the goal"
    assert_match(/\ASTATE goal: do the thing; read: nothing yet; evidence: 0\/\d+; done: needs exec evidence first\z/, ctx.last.text)
  end
end
