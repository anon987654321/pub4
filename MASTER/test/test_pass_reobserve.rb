# frozen_string_literal: true

require_relative "test_helper"

# After a repair the second reading covers the files the repair changed. The rest carry the first
# reading's counts, so a repair of a few files does not rescan the whole tree.
class TestPassReobserve < Minitest::Test
  Reobservation = Master::CLI::Pipeline::Reobservation
  Git = Struct.new(:paths) do
    def paths_since(_before) = paths
  end

  def setup
    @lib = File.join(Master::REPO_ROOT, "MASTER", "lib", "cli")
  end

  def reobservation(paths:, total: 10, counts: {})
    Reobservation.new(git: Git.new(paths), root: Master::ROOT, first_total: total, first_counts: counts)
  end

  def test_changed_files_inside_the_target_are_the_scope
    scope = reobservation(paths: ["MASTER/lib/cli/fold_risk.rb", "RAILS/README.md"]).scope("abc123", @lib)

    assert_equal [File.join(@lib, "fold_risk.rb")], scope.changed
  end

  def test_a_law_or_scanner_change_reads_everything_again
    ["MASTER/law/definition.rb", "MASTER/lib/review/scan/finding.rb", "MASTER/data/laws.yml"].each do |path|
      assert_nil reobservation(paths: [path]).scope("abc123", @lib), path
    end
  end

  def test_there_is_no_scope_without_a_base_commit_or_a_diff
    assert_nil reobservation(paths: ["MASTER/lib/cli/x.rb"]).scope(nil, @lib)
    assert_nil reobservation(paths: nil).scope("abc123", @lib)
  end

  def test_too_many_changed_files_read_the_whole_tree
    paths = Array.new(Reobservation::LIMIT + 1) { |index| "MASTER/lib/cli/file#{index}.rb" }

    assert_nil reobservation(paths:).scope("abc123", @lib)
  end

  def test_the_opt_out_reads_everything_again
    previous = ENV.fetch("MASTER_FIX_FULL_REOBSERVE", nil)
    ENV["MASTER_FIX_FULL_REOBSERVE"] = "1"

    assert_nil reobservation(paths: ["MASTER/lib/cli/x.rb"]).scope("abc123", @lib)
  ensure
    previous.nil? ? ENV.delete("MASTER_FIX_FULL_REOBSERVE") : ENV["MASTER_FIX_FULL_REOBSERVE"] = previous
  end

  def test_the_total_swaps_the_changed_files_old_counts_for_their_new_ones
    a = File.join(@lib, "a.rb")
    b = File.join(@lib, "b.rb")
    counts = { a => 30, b => 5, File.join(@lib, "c.rb") => 65 }

    assert_equal 100 - 30 - 5 + 2, reobservation(paths: [], total: 100, counts:).total([a, b], { a => 2 })
  end
end

# A file list is read as it is: no walk, one pair per file, and the counts reported per file.
class TestObserveFiles < Minitest::Test
  def test_only_the_named_files_are_scanned
    files = %w[fold_risk.rb session.rb].map { |name| File.join(Master::ROOT, "lib", "cli", name) }
    scanned = []
    scanner = Object.new
    scanner.define_singleton_method(:scan) { |path, **| scanned << path && [] }

    totals = []
    counted = []
    context = { args: "--dry-run", files:, on_counts: ->(counts) { counted << counts } }

    on_total = ->(total) { totals << total }

    Master::CLI::CommandRegistry.observe_files(scanner:, root: Master::ROOT, context:, on_total:)

    assert_equal files, scanned
    assert_equal [0], totals
    assert_equal [{}], counted
  end
end
