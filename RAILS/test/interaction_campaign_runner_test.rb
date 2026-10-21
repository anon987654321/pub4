# frozen_string_literal: true

require "digest"
require "json"
require "minitest/autorun"
require "stringio"
require "tmpdir"
require_relative "run_interaction_campaign"

class InteractionCampaignRunnerTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  MANIFEST = File.join(__dir__, "interaction_campaign_400.json")
  Runner = Operator::InteractionCampaignRunner

  class Status
    def initialize(success, exitstatus)
      @success = success
      @exitstatus = exitstatus
    end

    def success? = @success
    attr_reader :exitstatus
  end

  def test_mapped_case_runs_exact_test_and_saves_verifiable_evidence
    Dir.mktmpdir("interaction-campaign-evidence") do |evidence_root|
      calls = []
      executor = lambda do |command:, chdir:, timeout:|
        calls << { command:, chdir:, timeout: }
        ["1 runs, 4 assertions, 0 failures, 0 errors, 0 skips\n", Status.new(true, 0)]
      end
      out = StringIO.new
      runner = Runner.new(
        case_ids: ["RI-011"], root: ROOT, manifest_path: MANIFEST,
        evidence_root:, timeout: 30, io: out, executor:
      )

      assert_equal 0, runner.run
      assert_equal 1, calls.length
      assert_equal [
        "bin/rails", "test", "test/controllers/session_boundaries_test.rb",
        "--name", "\\Atest_RI_011_expired_session_with_csrf_failure_refuses_mutation\\z"
      ], calls.fetch(0).fetch(:command)
      assert_equal File.join(ROOT, "RAILS", "brgen"), calls.fetch(0).fetch(:chdir)
      assert_equal 30, calls.fetch(0).fetch(:timeout)

      results_path = Dir.glob(File.join(evidence_root, "**", "results.json")).first
      refute_nil results_path
      ledger = JSON.parse(File.read(results_path, encoding: "UTF-8"))
      assert_equal 1, ledger.fetch("results").length
      row = ledger.fetch("results").fetch(0)
      assert_equal "RI-011", row.fetch("case_id")
      assert_equal "PASS", row.fetch("status")
      assert_equal Digest::SHA256.file(MANIFEST).hexdigest, ledger.fetch("manifest_sha256")
      evidence = row.fetch("evidence")
      assert_equal evidence.fetch("test_sha256"), evidence.fetch("test_sha256_after")
      assert evidence.fetch("test_source_unchanged")
      assert_equal Digest::SHA256.file(File.join(ROOT, evidence.fetch("test_path"))).hexdigest,
                   evidence.fetch("test_sha256")
      log_path = File.join(File.dirname(results_path), evidence.fetch("log"))
      assert_equal Digest::SHA256.file(log_path).hexdigest, evidence.fetch("log_sha256")
      assert_equal Digest::SHA256.hexdigest("1 runs, 4 assertions, 0 failures, 0 errors, 0 skips\n"),
                   evidence.fetch("output_sha256")
      assert_equal "NOT_RUN", JSON.parse(File.read(MANIFEST)).fetch("cases")
                                        .find { |item| item.fetch("id") == "RI-011" }.fetch("runtime_status"),
                   "run-local evidence must not silently mutate the checked-in inventory"
    end
  end

  def test_unmapped_case_is_skipped_with_reason_and_never_calls_runner
    Dir.mktmpdir("interaction-campaign-skipped") do |evidence_root|
      called = false
      executor = lambda do |**|
        called = true
        ["1 runs, 1 assertions, 0 failures, 0 errors, 0 skips\n", Status.new(true, 0)]
      end
      runner = Runner.new(
        case_ids: ["RI-001"], root: ROOT, manifest_path: MANIFEST,
        evidence_root:, io: StringIO.new, executor:
      )

      assert_equal 3, runner.run
      refute called
      results_path = Dir.glob(File.join(evidence_root, "**", "results.json")).first
      results = JSON.parse(File.read(results_path)).fetch("results")
      assert_equal 1, results.length
      row = results.fetch(0)
      assert_equal "SKIPPED", row.fetch("status")
      assert_match(/no exact action\/fault adapter registered/, row.fetch("reason"))
      assert_nil row.fetch("evidence")
    end
  end

  def test_all_case_mode_cannot_report_success_while_cases_are_unmapped
    Dir.mktmpdir("interaction-campaign-all") do |evidence_root|
      executor = lambda do |**|
        ["1 runs, 4 assertions, 0 failures, 0 errors, 0 skips\n", Status.new(true, 0)]
      end
      runner = Runner.new(
        all: true, root: ROOT, manifest_path: MANIFEST,
        evidence_root:, io: StringIO.new, executor:
      )

      assert_equal 3, runner.run
      results_path = Dir.glob(File.join(evidence_root, "**", "results.json")).first
      ledger = JSON.parse(File.read(results_path))
      assert_equal 400, ledger.fetch("selected_case_count")
      assert_equal 1, ledger.fetch("counts").fetch("PASS")
      assert_equal 399, ledger.fetch("counts").fetch("SKIPPED")
    end
  end
  def test_file_level_success_is_blocked_when_more_than_one_test_ran
    Dir.mktmpdir("interaction-campaign-not-exact") do |evidence_root|
      executor = lambda do |**|
        ["5 runs, 100 assertions, 0 failures, 0 errors, 0 skips\n", Status.new(true, 0)]
      end
      runner = Runner.new(
        case_ids: ["RI-011"], root: ROOT, manifest_path: MANIFEST,
        evidence_root:, io: StringIO.new, executor:
      )

      assert_equal 3, runner.run
      results_path = Dir.glob(File.join(evidence_root, "**", "results.json")).first
      row = JSON.parse(File.read(results_path)).fetch("results").fetch(0)
      assert_equal "BLOCKED", row.fetch("status")
      assert_match(/exactly one executed mapped Minitest case/, row.fetch("reason"))
    end
  end


  def test_mapped_test_without_assertions_is_blocked
    Dir.mktmpdir("interaction-campaign-no-assertions") do |evidence_root|
      executor = lambda do |**|
        ["1 runs, 0 assertions, 0 failures, 0 errors, 0 skips\n", Status.new(true, 0)]
      end
      runner = Runner.new(
        case_ids: ["RI-011"], root: ROOT, manifest_path: MANIFEST,
        evidence_root:, io: StringIO.new, executor:
      )

      assert_equal 3, runner.run
      results_path = Dir.glob(File.join(evidence_root, "**", "results.json")).first
      row = JSON.parse(File.read(results_path)).fetch("results").fetch(0)
      assert_equal "BLOCKED", row.fetch("status")
      assert_match(/executed without assertions/, row.fetch("reason"))
    end
  end


  def test_saved_logs_redact_credentials_and_keep_distinct_hashes
    runner = Runner.allocate
    output = [
      "api_key=api-secret-value",
      "Authorization: Bearer bearer-secret-value",
      "Cookie: session=private-cookie-value",
      "github token ghp_abcdefghijklmnopqrstuvwxyz1234567890"
    ].join("\n")
    redacted = runner.send(:redact_output, output)

    assert_includes redacted, "api_key=<redacted>"
    assert_includes redacted, "Authorization: <redacted>"
    assert_includes redacted, "Cookie: <redacted>"
    refute_includes redacted, "api-secret-value"
    refute_includes redacted, "bearer-secret-value"
    refute_includes redacted, "private-cookie-value"
    refute_includes redacted, "ghp_abcdefghijklmnopqrstuvwxyz1234567890"
    refute_equal Digest::SHA256.hexdigest(output), Digest::SHA256.hexdigest(redacted)
  end


  def test_test_source_change_during_execution_blocks_attribution
    Dir.mktmpdir("interaction-campaign-source-race") do |root|
      manifest_path = File.join(root, "RAILS", "test", "interaction_campaign_400.json")
      test_path = File.join(root, "RAILS", "brgen", "test", "controllers", "session_boundaries_test.rb")
      rails_path = File.join(root, "RAILS", "brgen", "bin", "rails")
      FileUtils.mkdir_p(File.dirname(manifest_path))
      FileUtils.mkdir_p(File.dirname(test_path))
      FileUtils.mkdir_p(File.dirname(rails_path))
      File.write(manifest_path, File.read(MANIFEST))
      File.write(test_path, File.read(File.join(ROOT, "RAILS", "brgen", "test", "controllers", "session_boundaries_test.rb")))
      File.write(rails_path, "# fake app entrypoint\n")

      executor = lambda do |**|
        File.write(test_path, "# changed while the test ran\n")
        ["1 runs, 4 assertions, 0 failures, 0 errors, 0 skips\n", Status.new(true, 0)]
      end
      evidence_root = File.join(root, ".master", "interaction_campaign_runs")
      runner = Runner.new(
        case_ids: ["RI-011"], root:, manifest_path:, evidence_root:,
        io: StringIO.new, executor:
      )

      assert_equal 3, runner.run
      results_path = Dir.glob(File.join(evidence_root, "**", "results.json")).first
      row = JSON.parse(File.read(results_path)).fetch("results").fetch(0)
      assert_equal "BLOCKED", row.fetch("status")
      assert_match(/test source changed during execution/, row.fetch("reason"))
      assert_equal false, row.fetch("evidence").fetch("test_source_unchanged")
      refute_equal row.fetch("evidence").fetch("test_sha256"), row.fetch("evidence").fetch("test_sha256_after")
    end
  end

end
