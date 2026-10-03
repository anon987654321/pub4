# frozen_string_literal: true

require_relative "test_helper"

class FixConvergenceWiringTest < Minitest::Test
  def test_fix_loop_wires_rendered_and_opportunity_evidence
    loop_source = File.read(File.expand_path("../lib/fix/fix_loop.rb", __dir__))
    builder_source = File.read(File.expand_path("../lib/fix/fix_loop/pass_runner_builder.rb", __dir__))
    runner_source = File.read(File.expand_path("../lib/fix/fix_loop/pass_runner.rb", __dir__))
    evidence_source = File.read(File.expand_path("../lib/fix/fix_loop/pass_runner/evidence_stage.rb", __dir__))
    rule_source = File.read(File.expand_path("../lib/fix/rule_loop.rb", __dir__))

    assert_includes loop_source, 'require_relative "visual_pass"'
    assert_includes loop_source, 'require_relative "opportunity_pass"'
    assert_includes builder_source, "visual_pass:"
    assert_includes builder_source, "opportunity_pass:"

    assert_includes evidence_source, "run_visual_pass"
    assert_includes evidence_source, "run_opportunity_pass"
    assert_includes evidence_source, "run_visual_stage"
    assert_includes evidence_source, "run_opportunity_stage"
    assert_includes runner_source, "OpportunityPass::RULE_ID"

    assert_includes rule_source, "external_violations:"
    assert_includes rule_source, "image:"
    assert_includes rule_source, "@stage_commit"
  end

  def test_rendered_geometry_consumes_the_visual_measurement_payload
    geometry = File.read(File.expand_path("../../MASTER/gates/lib/rendered/rendered_geometry.rb", __dir__))
    walk = File.read(File.expand_path("../../MASTER/gates/support/geometry_probe/walk.js", __dir__))

    assert_includes walk, "visual"
    assert_includes walk, "first_screen"
    assert_includes walk, "typography"
    assert_includes geometry, "check_visual_composition"
    assert_includes geometry, "principle=hierarchy"
  end
end
