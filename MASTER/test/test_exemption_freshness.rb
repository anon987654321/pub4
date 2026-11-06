# frozen_string_literal: true

require "date"
require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "yaml"
require_relative "../checks/support/check_result"

module Master
  ROOT = File.expand_path("..", __dir__) unless const_defined?(:ROOT, false)
end

require_relative "../checks/lib/source/exemption_freshness"

# The rule the checks fixtures exist for: plant the defect, assert red and
# named, remove it, assert green. Every way a ledger row can rot is planted
# here — overdue review, vanished law, missing field, unparseable date — plus
# the two warn-only states (due soon, catalogue gap) and one test that runs the
# check against the real craft ledger, so the ledger and the law files cannot
# drift apart silently between campaigns.
class TestExemptionFreshnessCheck < Minitest::Test
  LAW = "LEDGER_FIXTURE_LAW"
  STALE = "2020-01-01"
  FRESH = "2099-01-01"

  def setup
    @repo = Dir.mktmpdir
    FileUtils.mkdir_p(File.join(@repo, "MASTER", "law"))
    File.write(File.join(@repo, "MASTER", "law", "fixture_law.rb"), <<~RUBY)
      Law.define(:#{LAW}) do
        severity :warn
      end
    RUBY
    @catalogue = File.join(@repo, "catalogue.yml")
    File.write(@catalogue, <<~YAML)
      #{LAW}:
        tier: hard
        statement: fixture law for ledger tests
    YAML
  end

  def teardown
    FileUtils.remove_entry(@repo)
  end

  def run_check(ledger_path, catalogue: @catalogue)
    Deploy::ExemptionFreshnessCheck.run(ledger_path:, catalogue_path: catalogue, law_root: @repo)
  end

  def write_ledger(rows)
    path = File.join(@repo, "ledger.yml")
    File.write(path, <<~YAML)
      schema: 1
      name: fixture_ledger
      exemptions:
      #{rows}
    YAML
    path
  end

  def row(id: "fixture-exemption", law: LAW, review_by: FRESH)
    <<~YAML.chomp
        - id: #{id}
          law: #{law}
          surface: fixture surface
          reason: fixture reason
          recorded: "2026-10-25"
          review_by: "#{review_by}"
    YAML
  end

  def test_overdue_review_fails_and_names_the_row
    result = run_check(write_ledger(row(id: "stale-row", review_by: STALE)))

    refute result.ok?, result.render
    assert_includes result.failures.join("\n"), "stale-row"
    assert_includes result.failures.join("\n"), "overdue"
  end

  def test_current_review_passes
    result = run_check(write_ledger(row))

    assert result.ok?, result.render
    assert_equal :passed, result.outcome
    assert_equal 1, result.checks_ran
  end

  def test_law_that_no_executable_file_declares_fails
    result = run_check(write_ledger(row(id: "dead-row", law: "VANISHED_LAW")))

    refute result.ok?, result.render
    assert_includes result.failures.join("\n"), "VANISHED_LAW"
    assert_includes result.failures.join("\n"), "no longer exists"
  end

  def test_row_missing_a_promised_field_fails
    ledger = write_ledger(<<~YAML.chomp)
        - id: incomplete-row
          law: #{LAW}
          surface: fixture surface
          recorded: "2026-10-25"
    YAML
    result = run_check(ledger)

    refute result.ok?, result.render
    assert_includes result.failures.join("\n"), "incomplete-row"
    assert_match(/missing.*reason.*review_by/, result.failures.join("\n"))
  end

  def test_unparseable_review_date_fails
    result = run_check(write_ledger(row(id: "bad-date-row", review_by: "not-a-date")))

    refute result.ok?, result.render
    assert_includes result.failures.join("\n"), "not a date"
  end

  def test_review_due_soon_warns_without_failing
    soon = (Date.today + 10).iso8601
    result = run_check(write_ledger(row(id: "due-soon", review_by: soon)))

    assert result.ok?, result.render
    assert_includes result.warnings.join("\n"), "due #{soon}"
  end

  def test_catalogue_gap_warns_but_does_not_fail
    File.write(@catalogue, "SOME_OTHER_LAW:\n  tier: hard\n")
    result = run_check(write_ledger(row))

    assert result.ok?, result.render
    assert_includes result.warnings.join("\n"), "reconciliation gap"
  end

  def test_missing_ledger_is_incomplete_never_green
    result = Deploy::ExemptionFreshnessCheck.run(
      ledger_path: File.join(@repo, "absent.yml"), catalogue_path: @catalogue, law_root: @repo,
    )

    assert result.incomplete?
    assert_equal :inconclusive, result.outcome
  end

  def test_empty_exemptions_pass_with_nothing_measured_claimed
    result = run_check(write_ledger(""))

    assert result.ok?, result.render
    assert_equal 0, result.checks_ran
  end

  # The standing guard: the shipped ledger against the shipped law files. The
  # two exemption rows recorded by the 2026-10-25 campaign must still resolve —
  # if a law file ever renames or retires NO_INLINE_SCRIPT_BLOCK, this goes red
  # in the same rake test run that broke it.
  def test_real_craft_ledger_rows_resolve_against_real_law_files
    result = Deploy::ExemptionFreshnessCheck.run

    assert_instance_of Deploy::CheckResult, result
    refute result.errored?, result.errors.join("\n")
    assert result.ok?, result.render
    assert_equal 2, result.checks_ran
  end
end
