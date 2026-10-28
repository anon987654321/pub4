# frozen_string_literal: true

require_relative "test_helper"

class FixConvergenceWiringTest < Minitest::Test
  def test_fix_loop_wires_rendered_and_opportunity_evidence
    loop_source = File.read(File.expand_path("../lib/fix/kernel/convergence_adapter.rb", __dir__))
    compatibility_entrypoint = File.read(File.expand_path("../lib/fix/fix_loop.rb", __dir__))
    pass_source = File.read(File.expand_path("../lib/fix/fix_loop/pass_execution.rb", __dir__))
    lifecycle_source = File.read(File.expand_path("../lib/fix/fix_loop/lifecycle.rb", __dir__))
    completion_source = File.read(File.expand_path("../lib/fix/fix_loop/completion.rb", __dir__))
    builder_source = File.read(File.expand_path("../lib/fix/fix_loop/pass_runner_builder.rb", __dir__))
    runner_source = File.read(File.expand_path("../lib/fix/fix_loop/pass_runner.rb", __dir__))
    evidence_source = File.read(File.expand_path("../lib/fix/fix_loop/pass_runner/evidence_stage.rb", __dir__))
    llm_source = File.read(File.expand_path("../lib/fix/fix_loop/pass_runner/llm_stage.rb", __dir__))
    wishlist_source = File.read(File.expand_path("../lib/fix/wishlist.rb", __dir__))
    journal_source = File.read(File.expand_path("../lib/fix/kernel/lifecycle_journal.rb", __dir__))
    repair_source = File.read(File.expand_path("../lib/fix/kernel/repair_adapter.rb", __dir__))

    assert_includes loop_source, 'require_relative "../visual_pass"'
    assert_includes compatibility_entrypoint, 'require_relative "kernel/convergence_adapter"'
    assert_includes loop_source, "class ConvergenceAdapter"
    assert_includes loop_source, 'require_relative "../opportunity_pass"'
    assert_includes builder_source, "visual_pass:"
    assert_includes builder_source, "opportunity_pass:"
    assert_includes builder_source, "wishlist:"

    assert_includes evidence_source, "run_visual_pass"
    assert_includes evidence_source, "run_opportunity_pass"
    assert_includes evidence_source, "run_visual_stage"
    assert_includes evidence_source, "run_opportunity_stage"
    assert_includes runner_source, "Wishlist.findings"
    assert_includes llm_source, "run_wishlist_stage"
    assert_includes llm_source, "Wishlist::LAW_ID"
    assert_includes loop_source, 'require_relative "../fix_loop/pass_execution"'
    assert_includes loop_source, 'require_relative "../fix_loop/lifecycle"'
    assert_includes loop_source, 'require_relative "../fix_loop/completion"'
    assert_includes pass_source, "continue_with_wishlist"
    assert_includes pass_source, "WISHLIST_MAX_ROUNDS"
    assert_includes lifecycle_source, "verify_incremental_scope"
    assert_includes completion_source, "finish_run"
    assert_includes wishlist_source, 'LEDGER_PATH = ".master/fix_wishlist.json"'
    refute_includes wishlist_source, "runtime/wishlist.md"
    assert_includes journal_source, "def remaining_seconds(run_id)"
    assert_includes runner_source, "OpportunityPass::LAW_ID"

    assert_includes repair_source, "external_violations:"
    assert_includes repair_source, "image:"
    assert_includes repair_source, "@stage_commit"
    assert_includes repair_source, 'require_relative "../../review/scan/law_health"'
    refute_includes repair_source, 'require_relative "../review/scan/law_health"'
  end

  def test_rendered_geometry_consumes_the_visual_measurement_payload
    geometry = File.read(File.expand_path("../../MASTER/checks/lib/rendered/rendered_geometry.rb", __dir__))
    walk = File.read(File.expand_path("../../MASTER/checks/support/geometry_probe/walk.js", __dir__))

    assert_includes walk, "visual"
    assert_includes walk, "first_screen"
    assert_includes walk, "typography"
    assert_includes geometry, "check_visual_composition"
    assert_includes geometry, "geometry hierarchy:"
  end
end
