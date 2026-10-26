# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require_relative "../law/detectors/external_linter_laws"

# A /fix whose instruments are broken stops in seconds and says why, instead of reading for an hour
# and ending with "incomplete, failed fix, proof".
class TestFixFailFast < Minitest::Test
  Pass = Master::CLI::Pipeline::Pass

  def pass(broken:)
    loop_ = Object.new
    loop_.define_singleton_method(:instrument_failures) { broken }
    scanner = Object.new
    %i[scan scan_dir].each do |reading|
      scanner.define_singleton_method(reading) { |*| flunk("a broken instrument must stop the run before any read") }
    end
    Pass.new(scanner:, fix_loop: loop_, root: Master::ROOT)
  end

  def failed_result(failed_stages:, causes: {}, ok: false)
    Pass::Result.new(target: "MASTER", mode: "strict", sections: [], ok:, unit: "review0", failed_stages:, causes:)
  end

  def test_a_broken_instrument_stops_the_run_before_anything_is_read
    reason = "linter: rubocop: scan error, Configuration file not found: /x/.rubocop.yml"
    result = pass(broken: [reason]).call(target: Master::ROOT, apply: true, critique: false, aesthetic: false)

    assert_equal ["instruments"], result.failed_stages
    assert_equal reason, result.causes["instruments"]
    assert_includes result.sections.to_h.fetch("instruments"), reason
  end

  # The loop probes from the repository root, which has no .rubocop.yml; MASTER's judges every tree.
  def test_a_root_without_a_rubocop_config_is_judged_by_masters
    Dir.mktmpdir("no-rubocop-config") do |root|
      law = Master::Review::Scan::Laws::RubocopLaw.new(root:)
      seen = nil
      law.define_singleton_method(:linter_available?) { |_name| true }
      law.define_singleton_method(:linter_json) { |*argv| (seen = argv) && { "files" => [{ "offenses" => [] }] } }
      law.check("", path: "probe.rb")

      assert_equal File.join(Master::ROOT, ".rubocop.yml"), seen[seen.index("--config") + 1]
    end
  end

  def test_the_footer_names_the_cause
    result = failed_result(failed_stages: %w[fix proof], causes: { "fix" => "rubocop config not found" })

    assert_includes result.footer, "review0: incomplete, failed fix, proof"
    assert_includes result.footer, "review0: cause, fix: rubocop config not found"
    refute_includes result.footer, "cause, proof"
  end

  def test_a_footer_without_causes_is_the_old_footer
    refute_includes failed_result(failed_stages: [], ok: true).footer, "cause"
  end

  def test_the_error_the_check_reads_carries_the_cause
    footer = "review0: incomplete, failed fix, 650 findings\nreview0: cause, fix: rubocop config not found\n"
    message = Master::CLI::CommandRegistry.incomplete_fix_pipeline(footer).message

    assert_includes message, "review0: incomplete, failed fix, 650 findings"
    assert_includes message, "cause fix: rubocop config not found"
  end

  def test_the_opt_out_reports_nothing_broken
    check = Master::Fix::InstrumentCheck.new(root: Master::ROOT, probes: [])
    check.define_singleton_method(:failures) { ["disk: full"] }

    assert_empty check.broken(env: { "MASTER_FIX_INSTRUMENT_CHECK" => "0" })
  end

  def test_without_the_opt_out_the_failures_are_reported
    check = Master::Fix::InstrumentCheck.new(root: Master::ROOT, probes: [])
    check.define_singleton_method(:failures) { ["disk: full"] }

    assert_equal ["disk: full"], check.broken(env: {})
  end

# The report carries the patch the repair wrote, and a patch can quote these words.
  def test_a_patch_that_quotes_the_footer_is_not_a_failed_pipeline
    quoted = "+    assert_includes result.footer, \"review0: incomplete, failed fix\"\n"

    refute Master::CLI::CommandRegistry.incomplete_fix_pipeline?(quoted)
    assert Master::CLI::CommandRegistry.incomplete_fix_pipeline?("review0: incomplete, failed fix\n")
  end
end
