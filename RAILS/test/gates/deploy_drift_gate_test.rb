# frozen_string_literal: true

require "fileutils"
require "json"
require "minitest/autorun"
require "tmpdir"

# The stamp directory is read into a constant when the gate file loads, so the
# fixture has to exist before the require. One directory for the whole file, its
# contents rewritten per test: `Dir.mktmpdir` with a block would be gone by the
# time the gate reads it.
DRIFT_STAMPS = Dir.mktmpdir("deploy-drift-stamps")
Minitest.after_run { FileUtils.remove_entry(DRIFT_STAMPS) if File.directory?(DRIFT_STAMPS) }
ENV["PUB4_STAMP_DIR"] = DRIFT_STAMPS

require_relative "../../gates/lib/live/deploy_drift"

# deploy_drift is the gate the third state was invented for.
#
# It compares the SHA in /var/db/pub4/last_deploy_<app>.json against HEAD. Off the
# deploy host those stamps do not exist, and before GateResult#inconclusive! the
# shim printed "ok: no deploy drift detected" directly beneath its own warning
# saying nothing had been checked. So the interesting assertion here is not that
# it finds drift — it is that with no stamps it declines to claim anything, and
# names the deploy host as the missing precondition rather than leaving the reader
# to guess why a drift gate went quiet.
class DeployDriftGateTest < Minitest::Test
  GATE = Deploy::DeployDriftGate

  def setup
    FileUtils.rm_f(Dir.glob(File.join(DRIFT_STAMPS, "*.json")))
  end

  def stamp(app, sha:, status: "ok")
    File.write(File.join(DRIFT_STAMPS, "last_deploy_#{app}.json"),
               JSON.generate("sha" => sha, "status" => status, "at" => "2026-09-11T00:00:00Z"))
  end

  def head = `git -C #{GATE::ROOT} rev-parse HEAD`.strip

  # The third state, in the words the task's other ten gates are measured against.
  def test_with_no_stamps_it_declines_to_judge_rather_than_reporting_ok
    result = GATE.run

    assert_equal :inconclusive, result.outcome, "no stamps is not a clean deploy"
    assert_match(/no deploy stamps under #{Regexp.escape(DRIFT_STAMPS)}/, result.unchecked.join(" | "))
    assert_match(/only has something to compare on the deploy host/, result.unchecked.join(" | "))
    assert_empty result.failures, "an absent precondition is not a finding about the tree"
  end

  # The stamp is present and its SHA is HEAD, so nothing committed is unshipped.
  def test_a_stamp_at_head_passes_and_says_what_it_compared
    stamp("brgen", sha: head)
    result = GATE.run

    assert_equal :passed, result.outcome, result.failures.join(" | ")
    assert_match(/compared 1 app\(s\) against HEAD #{head[0, 9]}/, result.warnings.join(" | "))
  end

  # ci_ok means CI passed and vps-deploy had not finished. Only "ok" means the
  # app is running that SHA, and a gate that accepted either would report a
  # half-finished deploy as live.
  def test_a_stamp_whose_status_is_not_ok_is_named
    stamp("brgen", sha: head, status: "ci_ok")

    assert_match(/brgen last deploy status is "ci_ok", not "ok"/, GATE.run.failures.join(" | "))
  end

  def test_a_stamp_with_no_sha_is_named
    File.write(File.join(DRIFT_STAMPS, "last_deploy_amber.json"), JSON.generate("status" => "ok"))

    assert_match(/amber stamp has no sha/, GATE.run.failures.join(" | "))
  end

  # The whole point of the gate: what is deployed is behind what is committed.
  # HEAD~1 is deployed, so every commit since then that touches the app is drift.
  def test_a_stamp_behind_head_names_the_unshipped_commits
    previous = `git -C #{GATE::ROOT} rev-parse HEAD~1`.strip
    skip "shallow checkout" if previous.empty?

    stamp("master", sha: previous)
    result = GATE.run
    drift = result.failures.grep(/master is running/)
    skip "HEAD~1 touched no MASTER path" if drift.empty?

    assert_match(/commit\(s\) since then touch MASTER\/web, MASTER\/lib, MASTER\/data/, drift.join)
  end

  # A SHA this checkout has never seen is not drift and not cleanliness — the gate
  # cannot compare, and saying so is the difference between the third state and a
  # guess in either direction.
  def test_a_deployed_sha_this_checkout_does_not_hold_is_inconclusive_not_a_failure
    stamp("bsdports", sha: "0" * 40)
    result = GATE.run

    assert_match(/deployed 0{40}, which this checkout does not contain/, result.unchecked.join(" | "))
    assert_empty result.failures, "an unfetched commit is not a drift finding"
  end
end
