# frozen_string_literal: true

require_relative "test_helper"
require "fix/work_lane"
require "fix/reachability"
require "cli/command_registry/review"

# A RAILS /fix measured for fifty minutes before its first repair. The lane decides which
# of those stages a run starts; these tests pin what each lane runs and skips.
class TestWorkLane < Minitest::Test
  Lane = Master::Fix::WorkLane

  def setup = @lane = Lane.current

  def teardown = Lane.restore(@lane)

  def test_code_is_the_default_and_starts_no_browser_research_or_architecture
    assert_equal :code, Lane::DEFAULT
    assert Lane.runs?(:code_passes, :code)
    %i[research architecture layout_sweep browser_checks visual_pass visual_groups].each do |stage|
      refute Lane.runs?(stage, :code), "code lane must skip #{stage}"
    end
  end

  def test_visual_sweeps_once_and_groups_without_the_code_passes
    %i[layout_sweep browser_checks visual_groups].each { |stage| assert Lane.runs?(stage, :visual), stage }
    %i[research architecture visual_pass code_passes].each do |stage|
      refute Lane.runs?(stage, :visual), "visual lane must skip #{stage}"
    end
  end

  def test_all_keeps_every_stage_fix_ran_before_lanes
    %i[research architecture layout_sweep browser_checks visual_pass code_passes].each do |stage|
      assert Lane.runs?(stage, :all), "all lane must run #{stage}"
    end
  end

  def test_the_summary_names_the_lane_and_what_it_skipped
    summary = Lane.summary(:code)

    assert_includes summary, "lane=code"
    assert_includes summary, "layout sweep"
    assert_includes summary, "research0 web research"
    assert_includes summary, "rendered findings are not measured or proven"
    refute_includes Lane.summary(:visual), "not measured"
  end

  def test_visual_lane_is_rails_only
    assert_nil Lane.refusal("RAILS", :visual)
    assert_nil Lane.refusal(File.join(Master::REPO_ROOT, "RAILS", "brgen"), :visual)
    assert_match(/RAILS/, Lane.refusal("MASTER", :visual))
    assert_nil Lane.refusal("MASTER", :code)
  end

  def test_unknown_lane_is_refused
    assert_raises(ArgumentError) { Lane.parse("fast") }
    assert_equal :visual, Lane.parse("Visual")
  end
end

# Where the lane reaches: the /fix flag, the child check runner, the layout suite and the
# fleet check that starts the sweep.
class TestWorkLaneWiring < Minitest::Test
  Lane = Master::Fix::WorkLane

  def setup = @lane = Lane.current

  def teardown = Lane.restore(@lane)

  def test_fix_reads_the_lane_flag_per_dispatch_and_keeps_it_out_of_the_target
    registry = Master::CLI::CommandRegistry

    assert_equal "visual", registry.execution_overrides("RAILS --lane=visual")[:lane]
    assert_equal "code", registry.execution_overrides("RAILS")[:lane]
    assert_equal "RAILS", registry.parse_pass_flags("RAILS --lane=code").last
  end

  def test_the_check_runner_is_told_the_lane
    assert_equal({ "CHECK_LANE" => "code" }, Lane.check_env(:code))
  end

  # The rendered suite is the 214-cell browser sweep; a code-lane proof measures the source leaves only.
  def test_the_layout_suite_leaves_out_the_rendered_suite_in_the_code_lane
    require File.expand_path("../checks/lib/layout_suite", __dir__)
    saved = ENV.fetch("CHECK_LANE", nil)

    ENV["CHECK_LANE"] = "code"
    refute_includes Deploy::LayoutSuiteCheck.new.leaves, Deploy::RenderedSuiteCheck
    ENV["CHECK_LANE"] = "visual"
    assert_includes Deploy::LayoutSuiteCheck.new.leaves, Deploy::RenderedSuiteCheck
  ensure
    saved.nil? ? ENV.delete("CHECK_LANE") : ENV["CHECK_LANE"] = saved
  end

  # The fleet check verifies wiring in every lane; only a lane that renders starts the sweep.
  def test_reachability_starts_the_layout_sweep_only_in_a_rendering_lane
    rails = File.join(Master::REPO_ROOT, "RAILS")
    files = Master::Fix::FixLoop::FileCollector.new(root: Master::ROOT).collect(rails)

    { code: [], visual: [:sweep], all: [:sweep] }.each do |lane, expected|
      Lane.set!(lane)
      sweeps = []
      reach = Master::Fix::Reachability.new(root: Master::ROOT)
      reach.define_singleton_method(:observe_layout_suite!) { sweeps << :sweep }
      reach.verify!(rails, files:)

      assert_equal expected, sweeps, "lane #{lane}"
    end
  end
end
