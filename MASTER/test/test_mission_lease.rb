# frozen_string_literal: true

require_relative "test_helper"
require "json"

# A worker delivers only while its mission runs under its own lease: a commit
# or push after another worker took the lease, or after the mission stopped,
# would land work nobody now owns.
class TestMissionLease < Minitest::Test
  def setup = @root = Dir.mktmpdir("mission-lease-")
  def teardown = FileUtils.rm_rf(@root)

  def claimed
    Master::Fix::Mission.new(root: @root).start_or_resume!(
      goal: "fix MASTER", scope: @root, model: "stub", effort: "high", plan: "observe", origin: "manual",
    )
  end

  def record = JSON.parse(File.read(File.join(@root, Master::Fix::Mission::REL_PATH)))

  def rewrite(**fields)
    path = File.join(@root, Master::Fix::Mission::REL_PATH)
    File.write(path, JSON.generate(record.merge(fields.transform_keys(&:to_s))))
  end

  def test_the_holder_renews_its_lease
    mission = claimed
    rewrite(lease_until: (Time.now.utc + 5).iso8601)

    mission.hold_lease!

    assert_operator Time.iso8601(record["lease_until"]), :>, Time.now.utc + 60
  end

  def test_a_lease_another_worker_took_is_refused
    mission = claimed
    rewrite(lease_owner: "another-host:1", lease_until: (Time.now.utc + 300).iso8601)

    error = assert_raises(Master::Fix::Mission::Fenced) { mission.hold_lease! }
    assert_match(/leased to another worker/, error.message)
  end

  def test_a_stopped_mission_is_refused
    mission = claimed
    Master::Fix::Mission.new(root: @root).finish!(state: "cancelled", summary: "operator stopped")

    error = assert_raises(Master::Fix::Mission::Fenced) { mission.hold_lease! }
    assert_match(/cancelled, not running/, error.message)
  end

  class Git
    attr_reader :commits

    def initialize = @commits = []
    def commit(message, paths:) = @commits << [message, paths]
  end

  def test_the_committer_commits_nothing_once_the_guard_refuses
    git = Git.new
    committer = Master::Fix::FixLoop::Committer.new(git:, root: @root)
    committer.lease_guard = -> { raise Master::Fix::Mission::Fenced, "mission m is leased to another worker" }

    assert_raises(Master::Fix::Mission::Fenced) { committer.commit_scoped("Repair", paths: ["a.rb"]) }
    assert_empty git.commits
  end
end
