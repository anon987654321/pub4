# frozen_string_literal: true

require_relative "test_helper"

# Run 2 of /fix MASTER on 2026-11-05 landed 6 and lost 13: 6 out_of_scope, the model editing lines
# outside the finding's range, and 5 reflexion_unsafe, mostly a dropped guard. The single-finding
# prompt named the finding's line but not the range the scope check enforces, and neither prompt
# named the guards the verifier holds a change to. Each such proposal cost a model call.
class TestFixRepairPromptScope < Minitest::Test
  Rule = Struct.new(:id, :severity)

  def violation(path, line)
    Master::Fix::Violation.from_finding({ law: "TEST_RULE", severity: :warning, line:, message: "fix me" },
                                        file: path, ext: ".rb")
  end

  def test_the_single_finding_prompt_names_the_allowed_lines_and_the_guards
    Dir.mktmpdir do |root|
      path = File.join(root, "sample.rb")
      File.write(path, "x = 1\n" * 80)
      loop = Master::Fix::RepairLoop.new(law: Rule.new("TEST_RULE", :warning), agent: nil, scanner: nil, root:)

      prompt = loop.send(:build_prompt_for, violation: violation(path, 40), src: File.read(path), path:)

      assert_includes prompt, "Every changed line must lie between line 15 and line 65 of the target"
      assert_includes prompt, Master::Fix::RepairLoop::FileBudget::GUARD_NOTE
    end
  end

  def test_the_range_starts_at_line_one_and_a_lineless_finding_still_names_the_guards
    loop = Master::Fix::RepairLoop.new(law: Rule.new("TEST_RULE", :warning), agent: nil, scanner: nil, root: Dir.tmpdir)

    assert_includes loop.send(:allowed_lines_note, { line: 3 }), "between line 1 and line 28"
    assert_equal Master::Fix::RepairLoop::FileBudget::GUARD_NOTE, loop.send(:allowed_lines_note, { line: 0 })
  end
end
