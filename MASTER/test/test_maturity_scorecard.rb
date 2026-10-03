# frozen_string_literal: true

require_relative "test_helper"

class TestMaturityScorecard < Minitest::Test
  FIXTURE = <<~YAML
    schema: 1
    subsystems:
      thing_one:
        status: verified
        meaning: does the thing reliably
        evidence: commit abc123, test_thing_one.rb
        last_checked: '2026-01-01'
      thing_two:
        status: smoke
        meaning: mostly works, only unit-tested
        evidence: test_thing_two.rb
        last_checked: '2026-01-02'
  YAML

  # Matches OpenClaw's taxonomy.yaml -- a scorecard of what's actually
  # proven, not just claimed, embodying soul.yml's own SURFACE_ERRORS_FIRST
  # / anti_simulation rules.
  def test_loads_subsystems_and_summary_line
    Dir.mktmpdir do |root|
      write_fixture(root)
      card = Master::Ground::MaturityScorecard.load(root:)

      assert_equal 2, card.subsystems.size
      assert_equal "maturity: 2 subsystems tracked (verified=1 smoke=1 broken=0), 0 unchecked for over 30 days",
                   card.summary_line(today: Date.new(2026, 1, 20))
    end
  end

  # Both directions, and the boundary named rather than a date well past it:
  # the shelf life is what makes `verified` mean something, so the day it
  # expires is the assertion.
  def test_evidence_older_than_the_shelf_life_reads_stale
    Dir.mktmpdir do |root|
      write_fixture(root)
      card = Master::Ground::MaturityScorecard.load(root:)

      assert_empty card.stale(today: Date.new(2026, 1, 31))
      assert_equal %w[thing_one], card.stale(today: Date.new(2026, 2, 1)).map(&:id)
      assert_equal %w[thing_one thing_two], card.stale(today: Date.new(2026, 3, 1)).map(&:id)
    end
  end

  def test_an_unparseable_date_reads_stale_rather_than_fresh
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "data"))
      File.write(File.join(root, "data", "maturity.yml"),
                 FIXTURE.sub("'2026-01-01'", "soon"))
      card = Master::Ground::MaturityScorecard.load(root:)

      assert_includes card.stale(today: Date.new(2026, 1, 2)).map(&:id), "thing_one"
    end
  end

  def test_by_status_filters_correctly
    Dir.mktmpdir do |root|
      write_fixture(root)
      card = Master::Ground::MaturityScorecard.load(root:)

      assert_equal %w[thing_one], card.by_status("verified").map(&:id)
      assert_equal %w[thing_two], card.by_status("smoke").map(&:id)
      assert_empty card.by_status("broken")
    end
  end

  # Matches Map::Principle's own fallback: a root with no maturity.yml of its
  # own reads the real repo's copy rather than coming up empty.
  def test_missing_file_falls_back_to_the_real_repo_copy
    Dir.mktmpdir do |root|
      card = Master::Ground::MaturityScorecard.load(root:)

      refute_empty card.subsystems
    end
  end

  private

  def write_fixture(root)
    FileUtils.mkdir_p(File.join(root, "data"))
    File.write(File.join(root, "data", "maturity.yml"), FIXTURE)
  end
end
