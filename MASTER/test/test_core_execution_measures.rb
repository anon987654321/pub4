# frozen_string_literal: true

require_relative "test_helper"

# The three measuring pieces of the execution tree: the bench that scores a
# pipeline against oracles, the curriculum that picks the task class failing
# most, and the capability map that counts how a model fails.
class TestCoreExecutionMeasures < Minitest::Test
  Episode = Struct.new(:intent, :outcome)

  def test_bench_scores_each_case_with_its_oracle
    bench = Master::Core::Execution::MasterBench.new
    bench.add_case("pass", ->(outcome) { outcome == "pass" ? 1.0 : 0.0 })
    bench.add_case("fail", ->(outcome) { outcome == "pass" ? 1.0 : 0.0 })
    pipeline = Object.new
    def pipeline.run(task) = task

    assert_equal({ mean: 0.5, pass_rate: 0.5 }, bench.run_all(pipeline))
  end

  def test_curriculum_drills_the_class_that_fails_most
    curriculum = Master::Core::Execution::SelfGeneratedCurriculum.new
    curriculum.analyze_episode(Episode.new(:refactor, :failed))
    curriculum.analyze_episode(Episode.new(:refactor, :done))
    curriculum.analyze_episode(Episode.new(:docs, :done))

    exercise = curriculum.generate_exercise

    assert_equal :refactor, exercise[:task]
    assert_equal :recovery_drill, exercise[:type]
  end

  def test_curriculum_has_nothing_to_drill_before_any_episode
    assert_nil Master::Core::Execution::SelfGeneratedCurriculum.new.generate_exercise
  end

  def test_empirical_map_counts_failure_modes_beside_outcomes
    map = Master::Core::Routing::EmpiricalCapabilityMap.new
    map.record_outcome("gemma", :coding, true)
    3.times { map.record_failure("gemma", :false_completion) }
    map.record_failure("gemma", :tool_error)

    assert_equal 0.75, map.failure_rate("gemma", :false_completion)
    assert_in_delta 0.0, map.failure_rate("qwen", :tool_error)
    assert_in_delta 1.0, map.success_rate("gemma", :coding)
  end
end
