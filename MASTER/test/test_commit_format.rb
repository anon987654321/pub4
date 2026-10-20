# frozen_string_literal: true

require_relative "test_helper"
require "open3"
require "tmpdir"

# MASTER's commit shape, defined in data/commit_format.yml: one definition for the runtime's own commits and
# for the commit-msg hook that holds every other author to them.
class TestCommitFormat < Minitest::Test
  Format = Master::Ground::CommitFormat
  HOOK = File.expand_path("../../OPENBSD/dev/githooks/commit-msg", __dir__)

  GOOD = "Gate preflight measures free space\n\nIt loaded the runtime first.\n\nCo-authored-by: MASTER"

  def test_a_message_in_masters_shape_has_no_problems
    assert_empty Format.problems(GOOD)
  end

  def test_the_body_is_optional_as_it_is_in_masters_own_commits
    assert_empty Format.problems("Fix the gate\n\nCo-authored-by: MASTER")
  end

  def test_each_departure_from_the_shape_is_named
    cases = {
      "feat(gate): fix the gate\n\nCo-authored-by: x" => /type prefix/,
      "fix: the gate\n\nCo-authored-by: x" => /type prefix/,
      "fix the gate\n\nCo-authored-by: x" => /lowercase/,
      "Fix the gate.\n\nCo-authored-by: x" => /ends with/,

      "#{"A" * 73}\n\nCo-authored-by: x" => /over 72/,
      "Fix the gate\nbody on line two\n\nCo-authored-by: x" => /blank line/,
      "Fix the gate\n\nwhat changed" => /trailer/,
      "Fix the gate" => /trailer/,
    }

    cases.each do |message, expected|
      found = Format.problems(message).any? { |problem| problem.match?(expected) }

      assert found, "#{message.inspect} should be #{expected}"
    end
  end

  def test_an_empty_message_is_refused
    assert_equal ["the message is empty"], Format.problems("  \n")
  end

  def test_the_runtime_subject_normaliser_agrees_with_the_checker
    raws = ["feat: add the gate.", "fix(scope)!: the gate!", "  spaced   out  "]

    raws.each do |raw|
      subject = Format.normalize_subject(raw)

      assert_empty Format.problems("#{subject}\n\nCo-authored-by: MASTER"), raw.inspect
    end
  end

  def run_hook(message, env: {})
    Dir.mktmpdir do |dir|
      file = File.join(dir, "COMMIT_EDITMSG")
      File.write(file, message)
      out, status = Open3.capture2e(env, RbConfig.ruby, HOOK, file)
      [status.exitstatus, out]
    end
  end

  def test_the_hook_passes_a_good_message_and_refuses_a_bad_one
    assert_equal 0, run_hook(GOOD).first

    code, out = run_hook("feat(x): do it.\n\nco-authored-by: x")

    assert_equal 1, code
    assert_includes out, "commit-msg:"
  end

  def test_the_hook_lets_merges_comments_and_the_opt_out_through
    assert_equal 0, run_hook("Merge branch 'x' into main\n").first
    assert_equal 0, run_hook("#{GOOD}\n# Please enter the commit message\n").first
    assert_equal 0, run_hook("bad.", env: { "PUB4_COMMIT_FORMAT" => "0" }).first
  end
end
