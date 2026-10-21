# frozen_string_literal: true

require "fileutils"
require "json"
require "minitest/autorun"
require "tmpdir"
require_relative "test_helper"
require_relative "../lib/fix/repair_loop"

class TestUserSimulation < Minitest::Test
  UserSimulation = Master::Fix::UserSimulation
  CAMPAIGN = File.join(Master::REPO_ROOT, "RAILS", "test", "interaction_campaign_400.json")

  def test_campaign_schema_and_runtime_evidence_are_validated
    campaign = JSON.parse(File.read(CAMPAIGN, encoding: "UTF-8"))

    assert_equal 400, campaign.fetch("cases").length
    assert_equal 20, campaign.fetch("surfaces").length
    assert_equal 20, campaign.fetch("fault_modes").length
    assert_equal 400, campaign.fetch("cases").map { |row| row.fetch("id") }.uniq.length

    campaign.fetch("cases").each do |row|
      assert_includes UserSimulation::RUNTIME_STATES, row.fetch("runtime_status")
      if %w[PASS FAIL].include?(row.fetch("runtime_status"))
        refute_empty row.fetch("runtime_evidence").to_s, "#{row.fetch("id")} requires runtime evidence"
      end
    end
  end

  def test_every_focused_test_mapping_points_to_a_real_test_file
    surfaces = JSON.parse(File.read(CAMPAIGN, encoding: "UTF-8")).fetch("surfaces")

    surfaces.each do |surface|
      name = surface.fetch("id")
      paths = surface.fetch("focused_test_paths")
      refute_empty paths, "#{name} has no focused test mapping"
      assert_equal paths.length, paths.uniq.length, "#{name} repeats a test path"

      paths.each do |relative|
        refute relative.start_with?("/"), "#{name}: absolute test path #{relative}"
        refute relative.split("/").include?(".."), "#{name}: test path escapes the repository"
        assert File.file?(File.join(Master::REPO_ROOT, relative)),
               "#{name}: focused test path is missing: #{relative}"
      end

      assert_equal paths, UserSimulation.new(root: Master::REPO_ROOT, campaign_path: CAMPAIGN).focused_test_paths_for(name),
                   "#{name}: runtime resolver diverged from the campaign manifest"
    end
  end

  def test_relevant_user_scenarios_are_prompted_as_oracles_not_results
    simulation = UserSimulation.new(root: Master::REPO_ROOT)
    path = File.join(Master::REPO_ROOT, "RAILS", "brgen", "app", "controllers", "posts_controller.rb")

    context = simulation.scenario_context(path:)

    assert_includes context, "USER-SIMULATION ORACLES"
    assert_includes context, "RI-021"
    assert_includes context, "not an executed test"
    assert_includes context, "inventory_state=NOT_RUN"
  end

  def test_candidate_approaches_are_materially_distinct_and_bounded
    approaches = (0...3).map { |index| UserSimulation.approach(index) }

    assert_equal 3, approaches.map { |row| row.fetch(:name) }.uniq.length
    assert_equal 3, approaches.map { |row| row.fetch(:instruction) }.uniq.length
    assert_operator UserSimulation.candidate_count, :>=, 2
    assert_operator UserSimulation.candidate_count, :<=, 5
  end

  def test_passing_candidate_is_tested_and_original_source_is_restored
    Dir.mktmpdir("master-user-simulation") do |root|
      path, tests = fixture_tree(root, "broken\n")
      runner = lambda do |_test_path|
        File.read(path).strip == "fixed" ?
          { state: :pass, signature: "pass" } :
          { state: :fail, signature: "baseline-failure" }
      end
      simulation = UserSimulation.new(root:, campaign_path: CAMPAIGN, runner:)
      writer = ->(target, text) { File.write(target, text) }

      results = simulation.evaluate_candidates(
        path:, original: "broken\n", candidates: ["fixed\n"], writer:
      )

      assert_equal :pass, results.fetch(0).fetch(:status)
      assert_equal tests.sort, results.fetch(0).fetch(:test_paths).sort
      assert_equal "broken\n", File.read(path)
    end
  end

  def test_candidate_introducing_failure_is_rejected_and_source_is_restored
    Dir.mktmpdir("master-user-simulation") do |root|
      path, = fixture_tree(root, "safe\n")
      runner = lambda do |_test_path|
        if File.read(path).strip == "safe"
          { state: :pass, signature: "pass" }
        else
          { state: :fail, signature: "new-failure" }
        end
      end
      simulation = UserSimulation.new(root:, campaign_path: CAMPAIGN, runner:)
      writer = ->(target, text) { File.write(target, text) }

      result = simulation.evaluate_candidates(
        path:, original: "safe\n", candidates: ["broken\n"], writer:
      ).fetch(0)

      assert_equal :regression, result.fetch(:status)
      refute_empty result.fetch(:regressions)
      assert_equal "safe\n", File.read(path)
    end
  end

  def test_unavailable_runner_is_blocked_not_passed
    Dir.mktmpdir("master-user-simulation") do |root|
      path, = fixture_tree(root, "safe\n")
      runner = ->(_test_path) { { state: :blocked, signature: "browser-unavailable", detail: "browser unavailable" } }
      simulation = UserSimulation.new(root:, campaign_path: CAMPAIGN, runner:)
      writer = ->(target, text) { File.write(target, text) }

      result = simulation.evaluate_candidates(
        path:, original: "safe\n", candidates: ["fixed\n"], writer:
      ).fetch(0)

      assert_equal :blocked, result.fetch(:status)
      refute_equal :pass, result.fetch(:status)
      assert_equal "safe\n", File.read(path)
    end
  end

  def test_candidate_simulation_never_overwrites_concurrent_source_changes
    Dir.mktmpdir("master-user-simulation") do |root|
      path, = fixture_tree(root, "safe\n")
      runner = lambda do |_test_path|
        File.write(path, "concurrent edit\n") if File.read(path).strip == "candidate"
        { state: :pass, signature: "pass" }
      end
      simulation = UserSimulation.new(root:, campaign_path: CAMPAIGN, runner:)
      writer = ->(target, text) { File.write(target, text) }

      error = assert_raises(UserSimulation::RestoreFailure) do
        simulation.evaluate_candidates(
          path:, original: "safe\n", candidates: ["candidate\n"], writer:
        )
      end

      assert_match(/refusing to overwrite concurrent content/, error.message)
      assert_equal "concurrent edit\n", File.read(path)
    end
  end

  def test_insufficient_file_budget_blocks_before_touching_source
    Dir.mktmpdir("master-user-simulation") do |root|
      path, = fixture_tree(root, "safe\n")
      write_called = false
      simulation = UserSimulation.new(
        root:, campaign_path: CAMPAIGN,
        deadline: Process.clock_gettime(Process::CLOCK_MONOTONIC) + 1
      )
      writer = lambda do |target, text|
        write_called = true
        File.write(target, text)
      end

      result = simulation.evaluate_candidates(
        path:, original: "safe\n", candidates: ["candidate\n"], writer:
      ).fetch(0)

      assert_equal :blocked, result.fetch(:status)
      assert_match(/file budget cannot reserve/, result.fetch(:reason))
      refute write_called
      assert_equal "safe\n", File.read(path)
    end
  end

  def test_missing_test_mapping_is_explicit_and_does_not_write_a_candidate
    Dir.mktmpdir("master-user-simulation") do |root|
      path = File.join(root, "misc", "sample.rb")
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, "original\n")
      write_called = false
      simulation = UserSimulation.new(root:, campaign_path: CAMPAIGN)
      writer = lambda do |target, text|
        write_called = true
        File.write(target, text)
      end

      result = simulation.evaluate_candidates(
        path:, original: "original\n", candidates: ["candidate\n"], writer:
      ).fetch(0)

      assert_equal :unavailable, result.fetch(:status)
      refute write_called, "no candidate source should be changed when there is no focused test"
      assert_equal "original\n", File.read(path)
    end
  end

  private

  def fixture_tree(root, source)
    path = File.join(root, "RAILS", "brgen", "app", "models", "post.rb")
    tests = UserSimulation.new(root:, campaign_path: CAMPAIGN).focused_test_paths_for("brgen_social")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, source)
    tests.each do |test_path|
      absolute = File.join(root, test_path)
      FileUtils.mkdir_p(File.dirname(absolute))
      File.write(absolute, "# isolated fake test path\n")
    end
    [path, tests]
  end
end
