# frozen_string_literal: true

require_relative "test_helper"

class TestProblemGraph < Minitest::Test
  Operation = Data.define(:position)

  class Plan
    ORDER = %w[defragment decouple flatten merge split relocate rename reorder remove reflow simplify recommend].freeze

    def operation(name)
      index = ORDER.index(name)
      raise KeyError, name unless index

      Operation.new(position: index)
    end
  end

  def setup
    @graph = Master::Fix::ProblemGraph.new(plan: Plan.new)
  end

  def finding(path, rule, message = rule, related = [])
    [path, rule, message, related]
  end

  def test_correlated_signals_become_one_multi_signal_problem
    rows = [
      finding("MASTER/lib/a.rb", "SMALL_FILES", "tiny owner", ["MASTER/lib/b.rb"]),
      finding("MASTER/lib/b.rb", "FILE_SPRAWL", "scattered files", ["MASTER/lib/a.rb"]),
    ]

    problems = @graph.call(rows)

    assert_equal 1, problems.size
    problem = problems.first
    assert problem.multi_signal?
    assert_equal 2, problem.size
    assert_equal %w[flatten merge remove simplify], problem.candidate_operations
    assert_equal %w[MASTER/lib/a.rb MASTER/lib/b.rb], problem.files
  end

  def test_unrelated_findings_stay_separate
    rows = [
      finding("MASTER/lib/a.rb", "SMALL_FILES"),
      finding("MASTER/lib/z.rb", "FILE_SPRAWL"),
    ]

    problems = @graph.call(rows)

    assert_equal 2, problems.size
    refute problems.first.multi_signal?
    refute problems.last.multi_signal?
  end

  def test_candidate_operations_are_unique_and_in_plan_order
    rows = [
      finding("MASTER/lib/a.rb", "CYCLIC_DEPENDENCY", "cycle", ["MASTER/lib/b.rb"]),
      finding("MASTER/lib/b.rb", "PARALLEL_HIERARCHY", "parallel", ["MASTER/lib/a.rb"]),
    ]

    problem = @graph.call(rows).first

    assert_equal %w[defragment decouple merge split relocate flatten simplify], problem.candidate_operations
    assert_equal %w[merge decouple], problem.primary_operations
  end

  def test_problem_is_bounded
    rows = 25.times.map { |index| finding("MASTER/lib/#{index}.rb", "SMALL_FILES") }
    problems = @graph.call(rows)

    assert_equal 25, problems.sum(&:size)
    assert problems.all? { |problem| problem.size <= Master::Fix::ProblemGraph::MAX_FINDINGS }
    assert problems.all? { |problem| problem.files.size <= Master::Fix::ProblemGraph::MAX_FILES }
  end

  def test_problem_identity_is_stable_for_same_observations
    rows = [
      finding("MASTER/lib/a.rb", "SMALL_FILES", "tiny"),
      finding("MASTER/lib/b.rb", "SMALL_FILES", "tiny"),
    ]

    assert_equal @graph.call(rows).first.id, @graph.call(rows).first.id
  end
end
