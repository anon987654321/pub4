# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../gates/lib/meta/constitutional_scan"

# The gate is four full MASTER scans, ~11 minutes end to end (brgen alone is
# ~4.5). These cover which targets it picks, which is the part worth changing
# and the only part cheap enough to test.
class ConstitutionalScanTargetsTest < Minitest::Test
  def build(changed:, changed_only: true)
    previous = ENV["GATE_SCAN_CHANGED"]
    ENV["GATE_SCAN_CHANGED"] = changed_only ? "1" : "0"
    gate = Deploy::ConstitutionalScanGate.allocate
    gate.define_singleton_method(:changed_paths) { changed }
    gate.send(:initialize)
    gate
  ensure
    previous ? ENV["GATE_SCAN_CHANGED"] = previous : ENV.delete("GATE_SCAN_CHANGED")
  end

  def names(paths) = paths.map { |path| File.basename(path) }

  # The gate asks MASTER for its lexical tier and nothing else. Without this
  # flag the runtime hands /scan an agent and every file costs a model round
  # trip: measured 2026-09-06, brgen alone ran 48 minutes of wall clock against
  # 35 seconds of CPU. With it, all four targets finish in under two minutes.
  # A per-app finding ceiling needs no model, and a gate nobody can afford to
  # run is a gate nobody runs.
  def test_the_scan_asks_for_the_deterministic_tier
    assert_equal "1", Deploy::ConstitutionalScanGate::SAFE_ENV["MASTER_SCAN_DETERMINISTIC"]
  end

  # And it is bounded. capture2e waited forever, so a stalled provider stopped
  # the whole gate run with no output and no verdict.
  def test_the_scan_has_a_finite_timeout
    assert_operator Deploy::ConstitutionalScanGate::SCAN_TIMEOUT_S, :>, 0
    assert_operator Deploy::ConstitutionalScanGate::SCAN_TIMEOUT_S, :<=, 3600
  end

  def test_scans_every_target_by_default
    gate = build(changed: [], changed_only: false)

    assert_equal %w[brgen amber bsdports shared], names(gate.targets)
    assert_empty gate.skipped
  end

  def test_changed_only_scans_just_the_apps_that_moved
    gate = build(changed: ["RAILS/brgen/app/models/post.rb", "MASTER/lib/master.rb"])

    assert_equal %w[brgen], names(gate.targets)
    assert_equal %w[amber bsdports shared], names(gate.skipped)
  end

  # Silent truncation reads as "covered everything". Whatever is dropped has to
  # be nameable, which is what #skipped is for.
  def test_skipped_targets_are_recorded_not_discarded
    gate = build(changed: ["RAILS/shared/app/models/concerns/shared/votable.rb"])

    assert_equal %w[shared], names(gate.targets)
    refute_empty gate.skipped
    assert_equal 4, gate.targets.size + gate.skipped.size
  end

  def test_no_changes_means_nothing_to_scan_not_everything
    gate = build(changed: ["OPENBSD/DECISIONS.md"])

    assert_empty gate.targets
    assert_equal 4, gate.skipped.size
  end

  # A path that merely contains an app's name must not select it.
  def test_selection_matches_on_the_app_directory_not_a_substring
    gate = build(changed: ["docs/brgen-notes.md", "RAILS/brgen_extra/thing.rb"])

    assert_empty gate.targets
  end
end
