# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../../MASTER/lib/operator/checks"

# The check scans six explicit constitutional targets, ~11 minutes end to end (brgen alone is
# ~4.5). These cover which targets it picks, which is the part worth changing
# and the only part cheap enough to test.
class ConstitutionalScanTargetsTest < Minitest::Test
  def build(changed:, changed_only: true)
    previous = ENV["CHECK_SCAN_CHANGED"]
    ENV["CHECK_SCAN_CHANGED"] = changed_only ? "1" : "0"
    check = Deploy::ConstitutionalScanCheck.allocate
    check.define_singleton_method(:changed_paths) { changed }
    check.send(:initialize)
    check
  ensure
    previous ? ENV["CHECK_SCAN_CHANGED"] = previous : ENV.delete("CHECK_SCAN_CHANGED")
  end

  def names(paths) = paths.map { |path| File.basename(path) }

  # The check asks MASTER for its lexical tier and nothing else. Without this
  # flag the runtime hands /scan an agent and every file costs a model round
  # trip: measured 2026-09-06, brgen alone ran 48 minutes of wall clock against
  # 35 seconds of CPU. With it, all six targets finish in under two minutes.
  # A per-app finding ceiling needs no model, and a check nobody can afford to
  # run is a check nobody runs.
  def test_the_scan_asks_for_the_deterministic_tier
    assert_equal "1", Deploy::ConstitutionalScanCheck::SAFE_ENV["MASTER_SCAN_DETERMINISTIC"]
  end

  # And it is bounded. capture2e waited forever, so a stalled provider stopped
  # the whole check run with no output and no verdict.
  def test_the_scan_has_a_finite_timeout
    assert_operator Deploy::ConstitutionalScanCheck::SCAN_TIMEOUT_S, :>, 0
    assert_operator Deploy::ConstitutionalScanCheck::SCAN_TIMEOUT_S, :<=, 3600
  end

  def test_scans_every_target_by_default
    check = build(changed: [], changed_only: false)

    assert_equal %w[brgen amber bsdports __shared OPENBSD MASTER], names(check.targets)
    assert_empty check.skipped
  end

  # Every tree, not the Rails half. MASTER judges every effect against its
  # constitution and the other trees are effects. The media tools live in
  # MASTER/tools since 9baa6047e, so the MASTER target covers them.
  def test_every_tree_is_a_target
    check = build(changed: [], changed_only: false)

    %w[OPENBSD MASTER].each do |tree|
      assert_includes names(check.targets), tree, "#{tree} is not scanned by the constitutional check"
    end
  end

  # A tree selects on its own name, an app on RAILS/<app>.
  def test_a_change_in_a_tree_selects_that_tree
    check = build(changed: ["OPENBSD/lib/check_result.rb"])

    assert_equal %w[OPENBSD], names(check.targets)
  end

  # Both, now that MASTER is a target of its own: a change under MASTER/lib used
  # to select nothing here, which is how the tree that owns the law went
  # unscanned by the check that applies it.
  def test_changed_only_scans_just_what_moved
    check = build(changed: ["RAILS/brgen/app/models/post.rb", "MASTER/lib/master.rb"])

    assert_equal %w[brgen MASTER], names(check.targets)
    assert_equal %w[amber bsdports __shared OPENBSD], names(check.skipped)
  end

  # Silent truncation reads as "covered everything". Whatever is dropped has to
  # be nameable, which is what #skipped is for.
  def test_skipped_targets_are_recorded_not_discarded
    check = build(changed: ["RAILS/__shared/app/models/concerns/shared/votable.rb"])

    assert_equal %w[__shared], names(check.targets)
    refute_empty check.skipped
    assert_equal 6, check.targets.size + check.skipped.size
  end

  # A path in no tree at all — OPENBSD is a target now, so the old example
  # selects one.
  def test_no_changes_means_nothing_to_scan_not_everything
    check = build(changed: ["docs/notes.md"])

    assert_empty check.targets
    assert_equal 6, check.skipped.size
  end

  def test_changed_path_inventory_includes_untracked_files_and_preserves_spaces
    previous = ENV["CHECK_SCAN_CHANGED"]
    ENV["CHECK_SCAN_CHANGED"] = "0"
    check = Deploy::ConstitutionalScanCheck.allocate
    check.send(:initialize)
    success = Struct.new(:ok) { def success? = ok }.new(true)
    calls = []
    capture = lambda do |*command, **_options|
      calls << command
      if command.include?("diff")
        [["MASTER/tracked.rb", ""].join(0.chr), success]
      elsif command.include?("ls-files")
        [["MASTER/untracked.rb", "RAILS/brgen/new file.rb", ""].join(0.chr), success]
      else
        flunk "unexpected command: #{command.inspect}"
      end
    end

    BoundedCommand.stub(:capture2e, capture) do
      assert_equal [
        "MASTER/tracked.rb",
        "MASTER/untracked.rb",
        "RAILS/brgen/new file.rb"
      ], check.send(:changed_paths)
    end
    assert calls.any? { |command| command.include?("--name-only") && command.include?("-z") }
    assert calls.any? { |command| command.include?("--others") && command.include?("--exclude-standard") && command.include?("-z") }
  ensure
    previous ? ENV["CHECK_SCAN_CHANGED"] = previous : ENV.delete("CHECK_SCAN_CHANGED")
  end

  def test_changed_only_with_no_applicable_target_is_inconclusive_not_a_pass
    check = build(changed: ["docs/notes.md"])

    result = check.run

    assert_empty check.targets
    assert_equal :inconclusive, result.outcome
    assert_includes result.unchecked.join("\n"), "no changed targets"
  end

  # A path that merely contains an app's name must not select it.
  def test_selection_matches_on_the_app_directory_not_a_substring
    check = build(changed: ["docs/brgen-notes.md", "RAILS/brgen_extra/thing.rb"])

    assert_empty check.targets
  end
end
