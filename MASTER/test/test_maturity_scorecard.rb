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
      assert_equal "maturity: 2 subsystems tracked (verified=1 smoke=1 broken=0)", card.summary_line
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
