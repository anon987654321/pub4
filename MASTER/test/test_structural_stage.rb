# frozen_string_literal: true

require_relative "test_helper"
# Through FixLoop, as production loads it: structural_stage.rb opens class
# FixLoop, whose autoload requires pass_runner.rb, which requires the stage
# back mid-load and finds StructuralStage undefined.
require_relative "../lib/fix/fix_loop"

class StructuralStageTest < Minitest::Test
  include Master::Fix::FixLoop::StructuralStage

  def test_structural_findings_require_actual_cohesion_evidence
    Dir.mktmpdir("structural") do |dir|
      File.write(File.join(dir, "thing_a.rb"), "def thing_a = 1\n")
      File.write(File.join(dir, "thing_b.rb"), "def thing_b = 2\n")
      File.write(File.join(dir, "thing_c.rb"), "def thing_c = 3\n")

      findings = structural_findings(files: Dir.glob(File.join(dir, "*.rb")))

      assert_empty findings, "a shared prefix alone is naming, not cohesion"
    end
  end

  def test_structural_findings_carry_laws_and_source
    Dir.mktmpdir("structural") do |dir|
      File.write(File.join(dir, "thing_a.rb"), "def thing_a = thing_b\n")
      File.write(File.join(dir, "thing_b.rb"), "def thing_b = thing_c\n")
      File.write(File.join(dir, "thing_c.rb"), "def thing_c = thing_a\n")

      finding = structural_findings(files: Dir.glob(File.join(dir, "*.rb"))).first

      assert_equal "cohesion", finding[:source]
      assert_equal %w[SINGULARITY ABSTRACTION DENSITY PROXIMITY KISS], finding[:laws]
      assert finding[:evidence].key?(:internal_references)
      assert finding[:evidence].key?(:external_references)
    end
  end

  def test_structural_findings_carry_external_reference_evidence
    Dir.mktmpdir("structural") do |dir|
      File.write(File.join(dir, "thing_a.rb"), "def thing_a = thing_b\n")
      File.write(File.join(dir, "thing_b.rb"), "def thing_b = thing_c\n")
      File.write(File.join(dir, "thing_c.rb"), "def thing_c = thing_a\n")
      findings = structural_findings(files: Dir.glob(File.join(dir, "*.rb")))

      assert_equal 1, findings.size
      assert_equal "STRUCTURAL_COHESION", findings.first[:rule]
      assert findings.first[:evidence].key?(:external_references)
    end
  end
end
