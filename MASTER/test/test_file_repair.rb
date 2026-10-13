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
      File.write(path, (["x = :bad"] + (["y = 1"] * 250)).join("\n") + "\n")
      agent = Agent.new("```diff\n--- a/sample.rb\n+++ b/sample.rb\n@@ -1,2 +1,2 @@\n-x = :bad\n+x = :good\n y = 1\n```")

      subject = repair(root, path, agent)
      result = subject.run(path)

      fixes = agent.prompts.reject { |prompt| prompt.include?("Verify this proposed") }
      assert_equal 1, fixes.size, "one fix call, no architecture plan, one candidate"
      assert_includes fixes.first, "FEW_ARGUMENTS"
      assert_includes fixes.first, "CQS"
      refute_includes fixes.first, "SMALL_FILES", "a split waits for a person"
      assert_operator fixes.first.bytesize, :<, 4_000, "the rules and a window of the file, not the 30 KB constitution or all 250 lines"
      assert_includes fixes.first, "minimal unified diff"
      assert_equal 1, result[:fixed]
      assert_equal "x = :good\n", File.readlines(path).first
      assert_equal %w[FEW_ARGUMENTS CQS], subject.asked_rules, "a split filtered out is not asked"
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
