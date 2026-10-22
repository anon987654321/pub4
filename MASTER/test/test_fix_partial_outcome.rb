# frozen_string_literal: true

require_relative "test_helper"
require "open3"
require "tmpdir"

# A /fix run that committed verified fixes and then stopped short is partial success, not failure.
class TestFixPartialOutcome < Minitest::Test
  Pass = Master::CLI::Pipeline::Pass

  def outcome(ok:, msg:, delivered: 0) = Pass.fix_outcome(ok:, msg:, delivered:)

  def test_a_clean_run_is_done
    assert_equal :done, outcome(ok: true, msg: "DONE: clean after 2 passes")
  end

  def test_a_plateau_after_commits_is_partial
    assert_equal :partial, outcome(ok: false, msg: "PLATEAU: no further improvement", delivered: 3)
    assert_equal :partial, outcome(ok: true, msg: "TIMEOUT: run budget spent", delivered: 1)
  end

  def test_a_plateau_with_no_commits_still_fails
    assert_equal :failed, outcome(ok: false, msg: "PLATEAU: no further improvement")
  end

  def test_fix_delivery_counter_matches_real_lowercase_subject_and_ignores_other_writers
    Dir.mktmpdir("fix-delivered-commits") do |root|
      git!(root, "init", "-q")
      git!(root, "config", "user.name", "Test")
      git!(root, "config", "user.email", "test@example.invalid")
      File.write(File.join(root, "file.rb"), "base\n")
      git!(root, "add", "--", "file.rb")
      git!(root, "commit", "-q", "-m", "baseline")
      head = git!(root, "rev-parse", "HEAD").strip

      File.write(File.join(root, "file.rb"), "fix\n")
      git!(root, "add", "--", "file.rb")
      git!(root, "commit", "-q", "-m", "fix_loop: pass 1", "-m", Master::Core::World::COMMIT_TRAILER)
      File.write(File.join(root, "file.rb"), "other\n")
      git!(root, "add", "--", "file.rb")
      git!(root, "commit", "-q", "-m", "ordinary writer", "-m", Master::Core::World::COMMIT_TRAILER)

      pass = Pass.allocate
      pass.instance_variable_set(:@root, root)
      assert_equal 1, pass.send(:fix_commits_since, head),
                   "the lowercase repair-loop commit must count, but another writer's shared trailer must not"
    end
  end

  def test_the_scorecard_says_what_the_run_did_and_left
    proof = { verdict: "proof: 9 of 20; no new failures", hard: %w[release], soft: %w[layout_suite tap_target_probe] }
    line = Pass.scorecard(outcome: :partial, delivered: 3, counts: [900, 412], proof:, gaps: 2)

    assert_equal "fix partial · 3 commit(s) delivered · 412 finding(s), was 900 · " \
                 "proof: 9 of 20; no new failures · hard red 1 (release) · soft red 2 · 2 gap(s)", line
  end

  def test_a_scorecard_without_a_proof_says_so
    assert_includes Pass.scorecard(outcome: :failed, delivered: 0, counts: [10]), "no proof ran"
  end

  def test_a_clean_run_with_a_hard_gate_red_is_partial
    proof = { verdict: "proof: 18 of 20", hard: %w[production], soft: [] }

    assert_match(/\Afix partial /, Pass.scorecard(outcome: :done, delivered: 1, proof:))
  end

  def test_the_scorecard_names_how_many_gates_went_unmeasured
    proof = { verdict: "proof: 18 of 20", hard: [], soft: [], unmeasured: %w[deploy_drift] }

    assert_includes Pass.scorecard(outcome: :done, delivered: 1, proof:), "unmeasured 1"
  end

  def test_a_clean_run_with_only_soft_gates_red_is_done
    proof = { verdict: "proof: 18 of 20", hard: [], soft: %w[layout_suite] }

    assert_match(/\Afix done /, Pass.scorecard(outcome: :done, delivered: 1, proof:))
  end

  private

  def git!(root, *args)
    output, status = Open3.capture2e("git", "-C", root, *args)
    assert status.success?, "git #{args.join(" ")} failed: #{output}"
    output
  end
end
