# frozen_string_literal: true

require_relative "test_helper"
require "minitest/mock"
require "tmpdir"
require_relative "../lib/operator/ratchet_cache"
require_relative "../lib/operator/ratchets"

# The ratchet stage cost 15 minutes before the first repair of the 2026-11-05 RAILS run and the same
# again after the last; the rows that read MASTER alone cannot move under a RAILS repair.
class TestRatchetCache < Minitest::Test
  Cache = Operator::RatchetCache
  Row = Operator::Ratchets::Row

  def setup
    @enabled = ENV["MASTER_RATCHET_CACHE"]
    ENV["MASTER_RATCHET_CACHE"] = "1"
  end

  def teardown = ENV["MASTER_RATCHET_CACHE"] = @enabled

  def with_repo
    Dir.mktmpdir("ratchet-cache") do |root|
      %w[MASTER RAILS].each do |tree|
        FileUtils.mkdir_p(File.join(root, tree))
        File.write(File.join(root, tree, "a.rb"), "x = 1\n")
      end

      git = ["git", "-C", root]
      system(*git, "init", "-q") && system(*git, "add", ".") &&
        system(*git, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "seed")
      @cache = Cache.new(root:, path: File.join(root, "cache.json"))
      yield root
    end
  end

  SELFTEST = Row.new(name: "selftest", current: 3, ceiling: 0, direction: :down)

  def measure(calls, row: SELFTEST)
    @cache.fetch("selftest", trees: %w[MASTER], row_class: Row) do
      calls << 1
      [row]
    end
  end

  def test_a_group_is_measured_again_only_when_its_own_tree_changes
    with_repo do |root|
      calls = []
      measure(calls)
      File.write(File.join(root, "RAILS", "a.rb"), "x = 2\n")
      rows = measure(calls)

      assert_equal 1, calls.size, "a RAILS edit moved a MASTER-only row"
      assert_equal [3, 0, :down], [rows.first.current, rows.first.ceiling, rows.first.direction]

      File.write(File.join(root, "MASTER", "new.rb"), "y = 1\n")
      measure(calls)
      assert_equal 2, calls.size, "an untracked MASTER file must count"
    end
  end

  def test_an_unreadable_row_is_never_kept
    with_repo do |root|
      calls = []
      blind = Row.new(name: "selftest", current: nil, ceiling: 0, direction: :down)
      2.times { measure(calls, row: blind) }

      assert_equal 2, calls.size
    end
  end

  # law_audit.blind and law_audit.saturated each ran the whole audit, about twenty minutes cold.
  def test_one_measurement_runs_the_law_audit_once
    require_relative "../lib/operator/law_audit"
    audits = 0
    report = { fixture_blindness: [], saturation: [] }
    Operator::LawAudit.stub(:audit, -> { (audits += 1) && report }) do
      Operator::Ratchets.instance_variable_set(:@law_audit, nil)
      Operator::Ratchets.law_reach_and_blind_rows + Operator::Ratchets.law_saturation_and_silent_rows
    end

    assert_equal 1, audits
  end
end
