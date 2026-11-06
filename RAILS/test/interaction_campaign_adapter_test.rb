# frozen_string_literal: true

require "digest"
require "json"
require "minitest/autorun"
require "stringio"
require "tmpdir"
require_relative "run_interaction_campaign"
require_relative "support/interaction_campaign_runner_sources"

class InteractionCampaignAdapterTest < Minitest::Test
  include InteractionCampaignRunnerSources

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

  def test_master_repair_case_resolves_to_exact_ruby_minitest
    exercise_runtime_adapter(
      case_id: "RI-341",
      source_path: "MASTER/test/test_repair_loop_policy.rb",
      source: "class RepairLoopFixtureTest\n  def test_RI_341_fix_repairs_known_small_defect_and_verifies\n    assert true\n  end\nend\n",
      adapter: {
        "runner" => "ruby_minitest",
        "path" => "MASTER/test/test_repair_loop_policy.rb",
        "name" => "test_RI_341_fix_repairs_known_small_defect_and_verifies"
      },
      output: "1 runs, 1 assertions, 0 failures, 0 errors, 0 skips\n",
      expected_command: ["ruby", "-Itest", "test_repair_loop_policy.rb", "--name",
                         "\\Atest_RI_341_fix_repairs_known_small_defect_and_verifies\\z"],
      expected_chdir_suffix: "/MASTER"
    )
  end

  def test_master_browser_case_resolves_to_exact_node_test_and_parses_tap
    exercise_runtime_adapter(
      case_id: "RI-281",
      source_path: "MASTER/web/test/campaign_case.test.mjs",
      source: "import test from \"node:test\"; import assert from \"node:assert/strict\";\ntest(\"test_RI_281_face_boot_ready_fallback\", () => { assert.equal(true, true); });\n",
      adapter: {
        "runner" => "node_test",
        "path" => "MASTER/web/test/campaign_case.test.mjs",
        "name" => "test_RI_281_face_boot_ready_fallback"
      },
      output: "TAP version 13\n# Subtest: test_RI_281_face_boot_ready_fallback\n    ok 1 - boot fallback exists\n    1..1\nok 1 - test_RI_281_face_boot_ready_fallback\n1..1\n# tests 1\n# suites 1\n# pass 1\n# fail 0\n# cancelled 0\n# skipped 0\n# todo 0\n",
      expected_command: ["node", "--test", "--test-reporter=tap", "--test-name-pattern",
                         "^test_RI_281_face_boot_ready_fallback$", "test/campaign_case.test.mjs"],
      expected_chdir_suffix: "/MASTER/web"
    )
  end

  def test_root_level_rails_node_test_uses_the_rails_working_directory
    exercise_runtime_adapter(
      case_id: "RI-361",
      source_path: "RAILS/test/pwa_offline_store.test.mjs",
      source: "import test from \"node:test\"; import assert from \"node:assert/strict\";\ntest(\"test_RI_361_pwa_manifest_contract\", () => { assert.equal(true, true); });\n",
      adapter: {
        "runner" => "node_test",
        "path" => "RAILS/test/pwa_offline_store.test.mjs",
        "name" => "test_RI_361_pwa_manifest_contract"
      },
      output: "TAP version 13\n# Subtest: test_RI_361_pwa_manifest_contract\n    ok 1 - manifest contract\n    1..1\nok 1 - test_RI_361_pwa_manifest_contract\n1..1\n# tests 1\n# suites 1\n# pass 1\n# fail 0\n# cancelled 0\n# skipped 0\n# todo 0\n",
      expected_command: ["node", "--test", "--test-reporter=tap", "--test-name-pattern",
                         "^test_RI_361_pwa_manifest_contract$", "test/pwa_offline_store.test.mjs"],
      expected_chdir_suffix: "/RAILS"
    )
  end
end
