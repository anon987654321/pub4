# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../contracts/studio"

# MASTER decides and reports; the STUDIO side here is a stub script, so nothing
# is heard, downloaded or separated.
class StudioHearDrumsContractTest < Minitest::Test
  DOSSIER = {
    "source_hash" => "a" * 64, "stem_hashes" => { "drums.wav" => "b" * 64 }, "tools" => {},
    "drum_pattern" => { "bpm" => 90.0 }, "engine_hints" => { "applied" => false }, "style_tags" => ["soul"]
  }.freeze

  def with_studio(body)
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "dilla"))
      File.write(File.join(root, "dilla", "dilla.rb"), "require \"json\"\n#{body}\n")
      original = ENV["PUB4_STUDIO_ROOT"]
      ENV["PUB4_STUDIO_ROOT"] = root
      yield
    ensure
      ENV["PUB4_STUDIO_ROOT"] = original
    end
  end

  def hear(**args) = Contracts::Studio.hear_drums(source: "/tmp/x.wav", authorized: true, **args)

  def test_unauthorized_requests_are_refused_without_running_studio
    with_studio('abort "must not run"') do
      result = Contracts::Studio.hear_drums(source: "/tmp/x.wav")
      assert_equal "refused", result["status"]
      assert_equal "policy", result["stage"]
    end
  end

  def test_network_sources_need_explicit_permission
    with_studio('abort "must not run"') do
      result = Contracts::Studio.hear_drums(source: "https://example.com/a", authorized: true)
      assert_equal "refused", result["status"]
      assert_match(/allow_network/, result["reason"])
    end
  end

  def test_duration_beyond_the_master_limit_is_refused
    with_studio('abort "must not run"') do
      [0, 121, "60", nil].each { |bad| assert_equal "refused", hear(max_seconds: bad)["status"] }
    end
  end

  def test_ok_requires_a_complete_dossier_from_studio
    report = JSON.generate("status" => "ok", "dossier_path" => "/x/v0001.json", "dossier" => DOSSIER)
    with_studio("puts #{report.inspect}") do
      result = hear(artist: "A", style_tags: ["soul"])
      assert_equal "ok", result["status"]
      assert_equal "available", result["capability"]
      assert_equal "a" * 64, result["dossier"]["source_hash"]
    end
  end

  def test_argv_carries_labels_and_an_absolute_source
    with_studio('puts JSON.generate("status" => "failed", "stage" => "x", "reason" => ARGV.join("|"))') do
      reason = Contracts::Studio.hear_drums(source: "rel.wav", authorized: true, artist: "A B", style_tags: %w[a b],
                                            max_seconds: 30)["reason"]
      assert_equal ["hear-drums", File.expand_path("rel.wav"), "--max-seconds", "30", "--artist", "A B", "--style", "a,b"],
                   reason.split("|")
    end
  end

  def test_ok_without_evidence_is_not_trusted
    with_studio('puts JSON.generate("status" => "ok")') do
      result = hear
      assert_equal "failed", result["status"]
      assert_equal "dispatch", result["stage"]
    end
  end

  def test_exit_code_zero_with_a_failed_report_is_a_failure
    with_studio('puts JSON.generate("status" => "failed", "stage" => "separate", "kind" => "tool_failed", "reason" => "demucs exited 3")') do
      result = hear
      assert_equal "failed", result["status"]
      assert_equal "separate", result["stage"]
      assert_equal "degraded: demucs exited 3", result["capability"]
    end
  end

  def test_missing_tool_reports_unavailable
    with_studio('puts JSON.generate("status" => "failed", "stage" => "separate", "kind" => "tool_unavailable", "reason" => "demucs is unavailable"); exit 1') do
      assert_equal "unavailable: demucs is unavailable", hear["capability"]
    end
  end

  def test_crash_with_no_report_is_a_failure
    with_studio("warn 'boom'; exit 2") do
      result = hear
      assert_equal "failed", result["status"]
      assert_match(/no report/, result["reason"])
    end
  end

  def test_nonzero_exit_with_an_ok_report_is_a_failure
    report = JSON.generate("status" => "ok", "dossier" => DOSSIER)
    with_studio("puts #{report.inspect}; exit 1") { assert_equal "failed", hear["status"] }
  end
end
