# frozen_string_literal: true

require_relative "test_helper"
require "json"

# The Fold keeps its mission under MASTER's root and /fix under the repository
# root (FixLoop#mission_root). A reader of one must not stand in for the other.
class TestMissionRoots < Minitest::Test
  class FixLoopDouble
    attr_reader :mission_root, :wakes

    def initialize(mission_root)
      @mission_root = mission_root
      @wakes = []
    end

    def wake_background!(reason:) = @wakes << reason
  end

  def setup
    @fold = Dir.mktmpdir("mission-fold-")
    @fix = Dir.mktmpdir("mission-fix-")
  end

  def teardown
    FileUtils.rm_rf([@fold, @fix])
  end

  def start_mission(root, goal)
    Master::Fix::Mission.new(root:).start_or_resume!(
      goal:, scope: root, model: "stub", effort: "high", plan: "observe", origin: "manual"
    )
  end

  def expire_lease(root)
    path = File.join(root, Master::Fix::Mission::REL_PATH)
    record = JSON.parse(File.read(path))
    record["state"] = "running"
    record["lease_until"] = "2000-01-01T00:00:00Z"
    File.write(path, JSON.generate(record))
  end

  def test_heartbeat_wakes_the_fix_mission_where_fix_loop_keeps_it
    start_mission(@fix, "fix RAILS")
    expire_lease(@fix)
    fix_loop = FixLoopDouble.new(@fix)

    Master::Fix::Heartbeat.new(root: @fold, fix_loop:).send(:reconcile_fix_mission!)

    assert_equal ["heartbeat:expired_lease"], fix_loop.wakes
  end

  def test_status_mission_names_both_missions
    start_mission(@fold, "answer the operator")
    start_mission(@fix, "fix RAILS")
    registry = Master::CLI::CommandRegistry

    text = registry.stub(:mission_roots, [["fold", @fold], ["fix", @fix]]) do
      registry.dispatch_mission(@fold, ctx: { args: "" })
    end

    assert_match(/mission: \S+ \(fold\)/, text)
    assert_match(/mission: \S+ \(fix\)/, text)
    assert_includes text, "goal: answer the operator"
    assert_includes text, "goal: fix RAILS"
  end

  def test_the_fix_root_for_master_is_the_repository_root
    roots = Master::CLI::CommandRegistry.mission_roots(Master::ROOT)

    assert_equal [["fold", Master::ROOT], ["fix", Master::REPO_ROOT]], roots
  end
end
