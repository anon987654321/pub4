# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

# One repair per file: every finding in one prompt, one candidate, no
# architecture plan. RepairLoop took about four calls a finding, one rule at a
# time, and /fix MASTER reached thirty-odd files an hour.
class TestFileRepair < Minitest::Test
  Rule = Struct.new(:id, :description)

  # Answers every prompt with the fixed file, and counts the prompts.
  class Agent
    attr_reader :prompts

    def initialize(answer) = (@answer = answer; @prompts = [])
    def ask(prompt, **) = (@prompts << prompt; @answer)
    def ask_once(prompt, **) = (@prompts << prompt; prompt.include?("Verify this proposed") ? "SAFE" : @answer)
  end

  # Findings shrink once the file changes, so the apply guard sees progress.
  class Scanner
    def scan(path, laws: nil)
      text = File.read(path)
      found = [{ law: "FEW_ARGUMENTS", severity: :warning, line: 1, message: "m" }]
      Master::Result.ok(text.include?("bad") ? found : [])
    end

    def should_autofix?(_rule_id, _confidence, allow_deletions: false) = true
  end

  def findings(path)
    [{ law: "FEW_ARGUMENTS", line: 1, message: "3+ positional args", file: path, severity: :warning },
     { law: "CQS", line: 2, message: "query mutates", file: path, severity: :warning },
     { law: "SMALL_FILES", line: 1, message: "split", file: path, severity: :warning,
       blast_radius: { files_touched: 2 } }]
  end

  def repair(root, path, agent)
    Master::Fix::FileRepair.new(findings: findings(path), agent:, scanner: Scanner.new, root:,
                                rules: [Rule.new("FEW_ARGUMENTS", "use keywords"), Rule.new("CQS", "split query")])
  end

  def test_one_prompt_carries_every_repairable_finding_and_no_constitution
    Dir.mktmpdir do |root|
      path = File.join(root, "sample.rb")
      source = (["x = :bad"] + (["y = 1"] * 248) + ["LAST_SOURCE_LINE = :seen"]).join("\n") + "\n"
      File.write(path, source)
      agent = Agent.new("```diff\n--- a/sample.rb\n+++ b/sample.rb\n@@ -1,2 +1,2 @@\n-x = :bad\n+x = :good\n y = 1\n```")

      subject = repair(root, path, agent)
      result = subject.run(path)

      fixes = agent.prompts.reject { |prompt| prompt.include?("Verify this proposed") }
      assert_equal 1, fixes.size, "one fix call, no architecture plan, one candidate"
      assert_includes fixes.first, "FEW_ARGUMENTS"
      assert_includes fixes.first, "CQS"
      refute_includes fixes.first, "SMALL_FILES", "a split waits for a person"
      assert_includes fixes.first, "Complete source, all 250 lines, no excerpts or omissions"
      assert_includes fixes.first, "LAST_SOURCE_LINE = :seen", "the complete target source must reach the model"
      assert_includes fixes.first, Digest::SHA256.hexdigest(source)
      assert_includes fixes.first, "minimal unified diff"
      assert_equal 1, result[:fixed]
      assert_equal "x = :good\n", File.readlines(path).first
      assert_equal %w[FEW_ARGUMENTS CQS], subject.asked_rules, "a split filtered out is not asked"
    end
  end
  # When callers cannot all be found, a repair may change a body and may not change what the file defines.
  def locked_repair(interface_locked, replacement)
    Dir.mktmpdir do |root|
      path = File.join(root, "sample.rb")
      File.write(path, "module Sample\n  def self.call = :bad\nend\n")
      diff = "```diff\n--- a/sample.rb\n+++ b/sample.rb\n@@ -1,3 +1,3 @@\n module Sample\n-  def self.call = :bad\n" \
             "+  #{replacement}\n end\n```"
      subject = Master::Fix::FileRepair.new(
        findings: [{ law: "TEST_RULE", line: 2, message: "replace bad value", file: path, severity: :warning }],
        rules: [Rule.new("TEST_RULE", "replace the bad value")],
        agent: Agent.new(diff), scanner: Scanner.new, root:
      )
      subject.lock_interface! if interface_locked

      yield subject.run(path), File.read(path)
    end
  end

  def test_a_locked_repair_may_change_a_body_but_not_a_name
    locked_repair(true, "def self.call = :good") do |result, text|
      assert_equal 1, result[:fixed]
      assert_includes text, ":good"
    end
  end

  def test_a_locked_repair_that_renames_a_method_is_refused_and_leaves_the_file
    locked_repair(true, "def self.other = :good") do |result, text|
      assert_equal 0, result[:fixed]
      assert_includes text, "def self.call = :bad"
    end
  end

  # A FileRepair over a one-method sample, answered by `agent`, with a finding at `line`.
  def sample_repair(root, agent, line: 2)
    path = File.join(root, "sample.rb")
    File.write(path, "module Sample\n  def self.call = :bad\nend\n")

    repair = Master::Fix::FileRepair.new(
      findings: [{ law: "TEST_RULE", line:, message: "m", file: path, severity: :warning }],
      rules: [Rule.new("TEST_RULE", "r")], agent:, scanner: Scanner.new, root:
    )
    [repair, path]
  end

  # A diff touching a line farther than SCOPE_PAD from every finding is refused, so the prompt says where the
  # edge is instead of spending a call and a retry to learn it.
  def test_the_prompt_names_the_lines_a_diff_may_touch
    Dir.mktmpdir do |root|
      agent = Agent.new("UNCHANGED")
      subject, path = sample_repair(root, agent, line: 40)

      subject.run(path)

      prompt = agent.prompts.reject { |item| item.include?("Verify this proposed") }.first
      assert_includes prompt, "Every changed line must lie between line 15 and line 65 of the target"
    end
  end

  # A diff that does not apply is saved with the hunks patch(1) refused; the trace collapses whitespace, which
  # is the evidence such a diff is made of.
  def test_a_diff_that_does_not_apply_is_saved_for_reading
    stale = "```diff\n--- a/sample.rb\n+++ b/sample.rb\n@@ -1,3 +1,3 @@\n module Sample\n" \
            "-  def self.call = :missing\n+  def self.call = :good\n end\n```"
    Dir.mktmpdir do |root|
      subject, path = sample_repair(root, Agent.new(stale))

      subject.run(path)

      diffs = Dir[File.join(root, ".master", "patch_rejects", "sample.rb.*")].grep(/\.diff\z/)
      refute_empty diffs
      assert_includes File.read(diffs.first), "-  def self.call = :missing"
      assert_includes File.read(diffs.first.sub(/\.diff\z/, ".rej")), ":missing"
    end
  end

  def test_an_unlocked_repair_may_rename
    locked_repair(false, "def self.other = :good") do |result, text|
      assert_equal 1, result[:fixed]
      assert_includes text, "def self.other"
    end
  end

  def test_prompt_includes_complete_dependency_and_caller_sources_with_hashes
    Dir.mktmpdir do |root|
      path = File.join(root, "sample.rb")
      source = "module Sample\n  VALUE = :bad\nend\n"
      dependency = "module SharedContract\n  CONTRACT_SENTINEL = :preserve\nend\n"
      File.write(path, source)
      agent = Agent.new("```diff\n--- a/sample.rb\n+++ b/sample.rb\n@@ -1,3 +1,3 @@\n module Sample\n-  VALUE = :bad\n+  VALUE = :good\n end\n```")
      subject = Master::Fix::FileRepair.new(
        findings: [{ law: "TEST_RULE", line: 2, message: "replace bad value", file: path, severity: :warning }],
        rules: [Rule.new("TEST_RULE", "replace the bad value")],
        agent:, scanner: Scanner.new, root:,
        context_files: [{
          path: "lib/shared_contract.rb",
          source: dependency,
          sha256: Digest::SHA256.hexdigest(dependency),
        }]
      )

      subject.run(path)

      prompt = agent.prompts.reject { |item| item.include?("Verify this proposed") }.first
      assert_includes prompt, "Related dependency/caller: lib/shared_contract.rb"
      assert_includes prompt, "CONTRACT_SENTINEL = :preserve"
      assert_includes prompt, Digest::SHA256.hexdigest(dependency)
    end
  end

  def test_stale_dependency_context_requires_a_human_decision_before_the_model_call
    Dir.mktmpdir("file-repair-stale-context") do |root|
      path = File.join(root, "lib", "sample.rb")
      dependency_path = File.join(root, "lib", "shared_contract.rb")
      FileUtils.mkdir_p(File.dirname(path))
      target_source = "module Sample\n  VALUE = :bad\nend\n"
      dependency = "module SharedContract\n  CONTRACT = :old\nend\n"
      File.write(path, target_source)
      File.write(dependency_path, dependency)
      agent = Agent.new("UNCHANGED")
      subject = Master::Fix::FileRepair.new(
        findings: [{ law: "TEST_RULE", line: 2, message: "replace bad value", file: path, severity: :warning }],
        rules: [Rule.new("TEST_RULE", "replace the bad value")],
        agent:, scanner: Scanner.new, root:,
        context_root: root,
        expected_target_sha256: Digest::SHA256.hexdigest(target_source),
        context_files: [{
          path: "lib/shared_contract.rb",
          source: dependency,
          sha256: Digest::SHA256.hexdigest(dependency),
        }]
      )
      File.write(dependency_path, dependency.sub(":old", ":new"))

      result = subject.run(path)

      assert_equal :human_decision, result[:status]
      assert_empty agent.prompts, "stale dependency context must be refused before asking the model"
      assert_equal target_source, File.read(path), "no edit may be made from stale context"
    end
  end

  # Asking again with the same prompt returned the same diff that had not applied. The second
  # prompt carries the failure, and only the second.
  class SequenceAgent < Agent
    def initialize(*answers) = (@answers = answers; @prompts = [])
    def ask(prompt, **) = (@prompts << prompt; @answers.shift || @answers.last)
  end

  def test_a_diff_that_did_not_apply_is_explained_in_the_second_prompt
    Dir.mktmpdir do |root|
      path = File.join(root, "sample.rb")
      File.write(path, (["x = :bad"] + (["y = 1"] * 20)).join("\n") + "\n")
      wrong = "```diff\n--- a/sample.rb\n+++ b/sample.rb\n@@ -1,2 +1,2 @@\n-x = :nowhere\n+x = :good\n y = 1\n```"
      right = "```diff\n--- a/sample.rb\n+++ b/sample.rb\n@@ -1,2 +1,2 @@\n-x = :bad\n+x = :good\n y = 1\n```"
      agent = SequenceAgent.new(wrong, right)

      capture_io { repair(root, path, agent).run(path) }

      fixes = agent.prompts.reject { |prompt| prompt.include?("Verify this proposed") }
      assert_equal 2, fixes.size
      refute_includes fixes.first, "did not apply"
      assert_includes fixes.last, "your diff did not apply to the file"
      assert_includes fixes.last, "copy every context line exactly"
      assert_equal "x = :good\n", File.readlines(path).first
    end
  end
end
