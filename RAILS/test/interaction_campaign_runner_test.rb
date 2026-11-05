# frozen_string_literal: true

require "digest"
require "json"
require "minitest/autorun"
require "stringio"
require "tmpdir"
require_relative "run_interaction_campaign"
require_relative "support/interaction_campaign_runner_sources"

class InteractionCampaignRunnerTest < Minitest::Test
  include InteractionCampaignRunnerSources

  def test_RI_001_executes_the_exact_signup_test
    Dir.mktmpdir("interaction-campaign-signup") do |evidence_root|
      calls = []
      executor = lambda do |command:, chdir:, timeout:|
        calls << { command:, chdir:, timeout: }
        ["1 runs, 4 assertions, 0 failures, 0 errors, 0 skips\n", Status.new(true, 0)]
      end
      runner = Runner.new(
        case_ids: ["RI-001"], root: ROOT, manifest_path: MANIFEST,
        evidence_root:, io: StringIO.new, executor:
      )

      assert_equal 0, runner.run
      assert_equal [{
        command: [
          "bin/rails", "test", "test/controllers/session_boundaries_test.rb",
          "--name", "\\Atest_RI_001_valid_signup_persists_unverified_account\\z"
        ],
        chdir: File.join(ROOT, "RAILS", "brgen"),
        timeout: Runner::DEFAULT_TIMEOUT
      }], calls
      results_path = Dir.glob(File.join(evidence_root, "**", "results.json")).first
      row = JSON.parse(File.read(results_path)).fetch("results").fetch(0)
      assert_equal "PASS", row.fetch("status")
      assert_equal "RI-001", row.fetch("case_id")
    end
  end

  def test_RI_003_executes_the_exact_malformed_email_test
    Dir.mktmpdir("interaction-campaign-email") do |evidence_root|
      calls = []
      executor = lambda do |command:, chdir:, timeout:|
        calls << { command:, chdir:, timeout: }
        ["1 runs, 2 assertions, 0 failures, 0 errors, 0 skips\n", Status.new(true, 0)]
      end
      runner = Runner.new(
        case_ids: ["RI-003"], root: ROOT, manifest_path: MANIFEST,
        evidence_root:, io: StringIO.new, executor:
      )

      assert_equal 0, runner.run
      assert_equal [{
        command: [
          "bin/rails", "test", "test/controllers/users_controller_test.rb",
          "--name", "\\Atest_RI_003_malformed_email_is_rejected_without_account\\z"
        ],
        chdir: File.join(ROOT, "RAILS", "brgen"),
        timeout: Runner::DEFAULT_TIMEOUT
      }], calls
      results_path = Dir.glob(File.join(evidence_root, "**", "results.json")).first
      row = JSON.parse(File.read(results_path)).fetch("results").fetch(0)
      assert_equal "PASS", row.fetch("status")
      assert_equal "RI-003", row.fetch("case_id")
    end
  end

  def test_RI_010_executes_the_exact_protected_route_test
    Dir.mktmpdir("interaction-campaign-authz") do |evidence_root|
      calls = []
      executor = lambda do |command:, chdir:, timeout:|
        calls << { command:, chdir:, timeout: }
        ["1 runs, 1 assertions, 0 failures, 0 errors, 0 skips\n", Status.new(true, 0)]
      end
      runner = Runner.new(
        case_ids: ["RI-010"], root: ROOT, manifest_path: MANIFEST,
        evidence_root:, io: StringIO.new, executor:
      )

      assert_equal 0, runner.run
      assert_equal [{
        command: [
          "bin/rails", "test", "test/integration/authorization_matrix_test.rb",
          "--name", "\\Atest_RI_010_unauthorized_actor_cannot_open_protected_community\\z"
        ],
        chdir: File.join(ROOT, "RAILS", "brgen"),
        timeout: Runner::DEFAULT_TIMEOUT
      }], calls
      results_path = Dir.glob(File.join(evidence_root, "**", "results.json")).first
      row = JSON.parse(File.read(results_path)).fetch("results").fetch(0)
      assert_equal "PASS", row.fetch("status")
      assert_equal "RI-010", row.fetch("case_id")
    end
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

  def test_list_validates_mapped_adapters_and_marks_missing_ones
    out = StringIO.new
    runner = Runner.new(
      root: ROOT, manifest_path: MANIFEST, io: out,
      executor: ->(**) { flunk("listing must not execute tests") }
    )

    assert_equal 0, runner.list
    assert_match(/^campaign0: RI-001 READY /, out.string)
    assert_match(/^campaign0: RI-003 READY /, out.string)
    assert_match(/^campaign0: RI-010 READY /, out.string)
    assert_match(/^campaign0: RI-011 READY /, out.string)
    assert_match(/^campaign0: RI-341 READY /, out.string)
    assert_match(/^campaign0: RI-002 UNMAPPED /, out.string)
    refute_includes out.string, "EXECUTABLE"
  end

  def test_unmapped_case_is_skipped_with_reason_and_never_calls_runner
    Dir.mktmpdir("interaction-campaign-skipped") do |evidence_root|
      called = false
      executor = lambda do |**|
        called = true
        ["1 runs, 1 assertions, 0 failures, 0 errors, 0 skips\n", Status.new(true, 0)]
      end
      runner = Runner.new(
        case_ids: ["RI-002"], root: ROOT, manifest_path: MANIFEST,
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
      counts = ledger.fetch("counts")
      assert_operator counts.fetch("PASS"), :>, 0
      assert_operator counts.fetch("SKIPPED"), :>, 0
      assert_equal ledger.fetch("selected_case_count"),
                   counts.fetch("PASS") + counts.fetch("SKIPPED")
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
end
