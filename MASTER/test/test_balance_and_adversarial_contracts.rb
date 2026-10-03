# frozen_string_literal: true

require "fileutils"
require "open3"

require_relative "test_helper"
require_relative "../lib/review/challenges"
require_relative "../tools/llm_challenges"
require_relative "../lib/core"
require_relative "../gates/support/gate_result"

class ReviewChallengePackTest < Minitest::Test
  def test_every_challenge_has_an_executable_artifact
    definitions = Master::Review::Challenges::DEFINITIONS

    assert_operator definitions.size, :>=, 10
    definitions.each do |challenge|
      refute_empty challenge.id.to_s
      refute_empty challenge.target
      refute_empty challenge.artifact
      refute_empty challenge.directive
    end
  end

  def test_solution_prompt_contains_the_whole_attack_pack
    prompt = Master::Review::Challenges.prompt(scope: :solution, evidence: "file: lib/core.rb")

    assert_includes prompt, "SOLUTION RED-TEAM"
    assert_includes prompt, "counterexample state"
    assert_includes prompt, "smallest deletion"
    Master::Review::Challenges::IDS.each { |id| assert_includes prompt, id.to_s }
    assert_operator prompt.index("SOLUTION RED-TEAM"), :<, prompt.index("1. mutation_guidance")
  end

  def test_operator_tool_emits_the_same_source_of_truth
    out, status = Open3.capture2e(
      RbConfig.ruby,
      File.expand_path("../tools/llm_challenges.rb", __dir__),
      "--mode", "pack",
      "--evidence", "probe"
    )

    assert_predicate status, :success?
    assert_includes out, "MASTER ADVERSARIAL CHALLENGE PACK"
    assert_includes out, "CURRENT EVIDENCE"
    assert_includes out, "probe"
  end
end

class WorldExternalContractTest < Minitest::Test
  def world(root)
    Master::Core::World.new(root:, capabilities: Master::Core::Capabilities.for(:fix))
  end

  def test_exec_captures_a_real_child_process
    Dir.mktmpdir("master-world") do |root|
      result = world(root).perform(
        Master::Core::Effect.exec([RbConfig.ruby, "-e", "STDOUT.write('world-ok')"], timeout: 3)
      )

      assert_predicate result, :ok?
      assert_equal "world-ok", result.message
    end
  end

  def test_exec_does_not_expose_credential_named_environment_variables
    previous = ENV["MASTER_PROBE_API_KEY"]
    ENV["MASTER_PROBE_API_KEY"] = "secret-value"

    Dir.mktmpdir("master-world") do |root|
      result = world(root).perform(
        Master::Core::Effect.exec(
          [RbConfig.ruby, "-e", "puts ENV.keys.grep(/MASTER_PROBE_API_KEY/).join(',')"],
          timeout: 3
        )
      )

      assert_predicate result, :ok?
      assert_equal "", result.message
    end
  ensure
    previous.nil? ? ENV.delete("MASTER_PROBE_API_KEY") : ENV["MASTER_PROBE_API_KEY"] = previous
  end

  def test_exec_timeout_is_a_failed_observation_and_returns
    Dir.mktmpdir("master-world") do |root|
      result = world(root).perform(
        Master::Core::Effect.exec([RbConfig.ruby, "-e", "sleep 4"], timeout: 1)
      )

      assert_predicate result, :err?
      assert_includes result.message, "TIMEOUT after"
    end
  end
\n  def test_scoped_rollback_preserves_an_unrelated_concurrent_file
    Dir.mktmpdir("master-world") do |root|
      Open3.capture2e("git", "-C", root, "init", "-q")
      Open3.capture2e("git", "-C", root, "config", "user.email", "master@example.invalid")
      Open3.capture2e("git", "-C", root, "config", "user.name", "MASTER")
      File.write(File.join(root, "tracked.txt"), "before\n")
      Open3.capture2e("git", "-C", root, "add", "tracked.txt")
      Open3.capture2e("git", "-C", root, "commit", "-qm", "seed")

      instance = world(root)
      checkpoint = instance.checkpoint
      effect = Master::Core::Effect.write("tracked.txt", "after\n")
      result = instance.perform(effect)
      assert_predicate result, :ok?

      File.write(File.join(root, "concurrent.txt"), "keep\n")
      rollback = instance.rollback(checkpoint, effect)

      assert_predicate rollback, :ok?
      assert_equal "before\n", File.read(File.join(root, "tracked.txt"))
      assert_equal "keep\n", File.read(File.join(root, "concurrent.txt"))
    end
  end
end

class GateOutcomeContractTest < Minitest::Test
  def setup
    @klass = Deploy::GateResult
  end

  def test_clean_gate_is_passed
    result = @klass.new.checked!
    assert_equal :passed, result.outcome
    assert_predicate result, :ok?
    assert_predicate result, :conclusive?
  end

  def test_all_live_skips_are_inconclusive_not_green
    result = @klass.new
    result.skipped_live("nothing listening")

    assert_equal :inconclusive, result.outcome
    refute result.conclusive?
    assert result.measured_nothing?
    assert_includes result.nothing_measured_reason, "nothing listening"
  end

  def test_gate_error_stays_distinct_from_a_failed_contract
    result = @klass.from_error(RuntimeError.new("boom"), gate: "example")

    assert_equal :errored, result.outcome
    assert result.errored?
    assert_predicate result, :ok?, "errored is fail-open unless strict gate mode is enabled"
  end

  def test_strict_inconclusive_blocks
    result = @klass.new
    result.inconclusive!("Chrome missing")

    assert_equal :inconclusive, result.outcome

    ENV["GATE_STRICT_INCONCLUSIVE"] = "1"
    assert_equal :failed, result.outcome
  ensure
    ENV.delete("GATE_STRICT_INCONCLUSIVE")
  end
end

class ChallengeToolBalanceTest < Minitest::Test
  def test_balance_report_measures_code_and_tests
    report = Master::Review::ChallengeTools.balance

    assert_operator report[:ruby_files], :>, 0
    assert_operator report[:test_files], :>, 0
    assert_operator report[:direct_test_ratio], :>=, 0.0
    assert_operator report[:direct_test_ratio], :<=, 1.0
    assert_kind_of Array, report[:large_ruby_files]
  end

  def test_history_mining_returns_structured_rows_without_needing_a_model
    rows = Master::Review::ChallengeTools.history(limit: 3)

    assert_kind_of Array, rows
    rows.each do |row|
      assert_match(/\A[0-9a-f]{40}\z/, row[:sha])
      refute_empty row[:subject]
      assert_kind_of Array, row[:tests]
    end
  end
\n  def test_test_deletion_probe_reports_unique_coverage
    Dir.mktmpdir("master-deletion") do |root|
      lib = File.join(root, "lib")
      FileUtils.mkdir_p(lib)
      File.write(File.join(lib, "tiny.rb"), <<~RUBY)
        module Tiny
          def self.alpha = "alpha"
          def self.beta = "beta"
        end
      RUBY
      path = File.join(root, "tiny_test.rb")
      File.write(path, <<~RUBY)
        require "minitest/autorun"
        require_relative "lib/tiny"

        class TinyTest < Minitest::Test
          def test_alpha_contract
            assert_equal "alpha", Tiny.alpha
          end

          def test_beta_contract
            assert_equal "beta", Tiny.beta
          end
        end
      RUBY

      report = Master::Review::ChallengeTools.deletion_probe(path)
      assert report[:baseline_ok], report[:errors].join("\n")
      assert_equal 2, report[:methods].size
      assert_kind_of Hash, report[:protected]
      assert_kind_of Array, report[:unprotected]
      assert_empty report[:unprotected]
      assert report[:protected].values.all? { |lines| !lines.empty? }
    end
  end

end
