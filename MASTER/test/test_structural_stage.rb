# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/fix/fix_loop/structural_stage"

class StructuralStageTest < Minitest::Test
  include Master::Fix::FixLoop::StructuralStage

  def test_structural_findings_require_actual_cohesion_evidence
    Dir.mktmpdir("structural") do |dir|
      File.write(File.join(dir, "thing_a.rb"), "def thing_a = thing_b\n")
      File.write(File.join(dir, "thing_b.rb"), "def thing_b = thing_c\n")
      File.write(File.join(dir, "thing_c.rb"), "def thing_c = thing_a\n")

      findings = structural_findings(files: Dir.glob(File.join(dir, "*.rb")))

      assert_empty findings, "three files that only form a naming family must not become a structural repair"
    end
  end

  def test_structural_findings_carry_external_reference_evidence
    Dir.mktmpdir("structural") do |dir|
      File.write(File.join(dir, "thing_a.rb"), "def thing_a = thing_b\n")
      File.write(File.join(dir, "thing_b.rb"), "def thing_b = thing_c\n")
      File.write(File.join(dir, "thing_c.rb"), "def thing_c = thing_a\n")
      File.write(File.join(dir, "caller.rb"), "thing_a\n")

      findings = structural_findings(files: Dir.glob(File.join(dir, "*.rb")))

      assert_equal 1, findings.size
      assert_equal "STRUCTURAL_COHESION", findings.first[:rule]
      assert findings.first[:message].include?("caller.rb")
    end
  end
end
