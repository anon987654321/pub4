# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "tmpdir"
require_relative "../../../MASTER/checks/lib/rendered/browser_diagnostics"

# One /fix RAILS run rendered the same 214 cells three times over an unchanged tree. A sweep
# recorded under a key replays its verdicts for that key, and only for that key.
class SweepReplayTest < Minitest::Test
  ROWS = [{ "app" => "brgen", "surface" => "posts_new", "viewport" => "mobile", "status" => "FAIL",
            "failure_reasons" => ["uncaught JavaScript exception"], "warnings" => ["console warning"] }].freeze

  def recorded_replay(dir)
    manifest = File.join(dir, "manifest.json")
    File.write(manifest, JSON.generate("results" => ROWS))
    replay = Deploy::SweepReplay.new(base: dir)

    replay.remember(key: "a" * 64, manifest:)
    replay
  end

  def test_the_same_key_hands_back_the_recorded_rows_and_another_does_not
    Dir.mktmpdir("sweep-replay") do |dir|
      replay = recorded_replay(dir)

      assert_equal ROWS, replay.rows("a" * 64)
      assert_nil replay.rows("b" * 64)
    end
  end

  def test_replay_can_be_switched_off
    Dir.mktmpdir("sweep-replay") do |dir|
      replay = recorded_replay(dir)
      previous = ENV["CHECK_BROWSER_DIAGNOSTICS_REPLAY"]
      ENV["CHECK_BROWSER_DIAGNOSTICS_REPLAY"] = "0"

      assert_nil replay.rows("a" * 64)
    ensure
      previous ? ENV["CHECK_BROWSER_DIAGNOSTICS_REPLAY"] = previous : ENV.delete("CHECK_BROWSER_DIAGNOSTICS_REPLAY")
    end
  end

  def test_a_replayed_sweep_reports_what_the_rendered_one_did
    result = nil
    capture_io { result = Deploy::BrowserDiagnosticsCheck.new.replayed(ROWS, since: Time.at(0)) }

    assert_includes result.failures.join("\n"), "brgen/posts_new/mobile — uncaught JavaScript exception"
  end

  def test_an_edit_to_rails_is_a_new_key
    replay = Deploy::SweepReplay.new(base: Dir.tmpdir)
    root = File.expand_path("../../..", __dir__)
    inputs = Deploy::SweepReplay.inputs(root:, check_code: __FILE__, live_ids: ["brgen/home/mobile"])

    refute_equal replay.key(inputs), replay.key(inputs + ["an edited stylesheet"])
  end
end
