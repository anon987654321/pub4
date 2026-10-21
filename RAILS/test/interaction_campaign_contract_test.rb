# frozen_string_literal: true

require "json"
require "minitest/autorun"

class InteractionCampaignContractTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  MANIFEST = File.join(__dir__, "interaction_campaign_400.json")
  REQUIRED_CASE_FIELDS = %w[
    id surface_id action_id fault_mode assessment runtime_status runtime_evidence
  ].freeze
  VALID_RUNTIME_STATES = %w[NOT_RUN PASS FAIL BLOCKED SKIPPED].freeze

  def setup
    @campaign = JSON.parse(File.read(MANIFEST))
  end

  def test_campaign_declares_four_hundred_cases_across_twenty_surfaces
    assert_equal 400, @campaign.fetch("case_count")
    assert_equal 20, @campaign.fetch("surface_count")
    assert_equal 20, @campaign.fetch("cases_per_surface")
    assert_equal 400, @campaign.fetch("cases").length
    assert_equal 20, @campaign.fetch("surfaces").length
  end

  def test_case_ids_are_unique_and_sequential
    ids = @campaign.fetch("cases").map { |row| row.fetch("id") }
    expected = (1..400).map { |number| format("RI-%03d", number) }

    assert_equal expected, ids
    assert_equal ids.length, ids.uniq.length
  end

  def test_every_surface_has_twenty_unique_actions_and_twenty_cases
    surfaces = @campaign.fetch("surfaces")
    ids = surfaces.map { |surface| surface.fetch("id") }
    grouped = @campaign.fetch("cases").group_by { |row| row.fetch("surface_id") }

    assert_equal ids.length, ids.uniq.length
    assert_equal ids.sort, grouped.keys.sort

    surfaces.each do |surface|
      actions = surface.fetch("actions")
      rows = grouped.fetch(surface.fetch("id"))

      assert_equal 20, surface.fetch("expected_cases")
      assert_equal 20, actions.length
      assert_equal 20, rows.length
      assert_equal (1..20).map { |n| format("%02d", n) }, actions.map { |action| action.fetch("id") }
      assert_equal actions.length, actions.map { |action| action.fetch("action") }.uniq.length
      refute_empty surface.fetch("actor").strip
      refute_empty surface.fetch("contract").strip
    end
  end

  def test_each_surface_covers_all_fault_modes_once
    known_faults = @campaign.fetch("fault_modes").map { |mode| mode.fetch("id") }
    assert_equal 20, known_faults.length
    assert_equal known_faults.length, known_faults.uniq.length

    @campaign.fetch("surfaces").each do |surface|
      rows = @campaign.fetch("cases").select { |row| row.fetch("surface_id") == surface.fetch("id") }
      observed = rows.map { |row| row.fetch("fault_mode") }

      assert_equal known_faults.sort, observed.sort, "#{surface.fetch("id")}: fault-mode coverage gap"
      assert_equal observed.length, observed.uniq.length, "#{surface.fetch("id")}: repeated fault mode"
    end
  end

  def test_each_case_resolves_to_one_existing_surface_action_and_fault_oracle
    surfaces = @campaign.fetch("surfaces").to_h { |surface| [surface.fetch("id"), surface] }
    faults = @campaign.fetch("fault_modes").to_h { |mode| [mode.fetch("id"), mode] }
    action_pairs = []

    @campaign.fetch("cases").each do |row|
      missing = REQUIRED_CASE_FIELDS.reject { |field| row.key?(field) }
      assert_empty missing, "#{row["id"]}: missing fields #{missing.join(", ")}"

      surface = surfaces.fetch(row.fetch("surface_id"))
      action = surface.fetch("actions").find { |item| item.fetch("id") == row.fetch("action_id") }
      fault = faults.fetch(row.fetch("fault_mode"))

      refute_nil action, "#{row.fetch("id")}: unknown action id"
      refute_empty action.fetch("action").strip
      refute_empty fault.fetch("setup").strip
      refute_empty fault.fetch("expected").strip
      action_pairs << [surface.fetch("id"), action.fetch("id")]
    end

    assert_equal action_pairs.length, action_pairs.uniq.length,
                 "a surface action is represented more than once"
  end

  def test_focused_test_paths_are_canonical_repository_files
    paths = @campaign.fetch("surfaces").flat_map do |surface|
      focused = surface.fetch("focused_test_paths")
      refute_empty focused, "#{surface.fetch("id")}: no focused test paths"
      assert_equal focused.length, focused.uniq.length,
                   "#{surface.fetch("id")}: duplicate focused test paths"
      focused
    end

    paths.each do |relative|
      refute relative.start_with?("/"), "absolute focused test path is not portable: #{relative}"
      refute relative.split("/").include?(".."), "focused test path escapes repository: #{relative}"
      assert File.file?(File.join(ROOT, relative)), "missing focused test path: #{relative}"
    end
  end

  def test_evidence_paths_are_repository_relative_and_exist
    paths = @campaign.fetch("surfaces").flat_map { |surface| surface.fetch("evidence_paths") }.uniq
    assert_operator paths.length, :>=, 20

    paths.each do |relative|
      refute relative.start_with?("/"), "absolute evidence path is not portable: #{relative}"
      refute relative.split("/").include?(".."), "evidence path escapes repository: #{relative}"
      assert File.file?(File.join(ROOT, relative)), "missing evidence path: #{relative}"
    end
  end

  def test_declared_runtime_adapters_resolve_to_existing_focused_test_methods
    surfaces = @campaign.fetch("surfaces").to_h { |surface| [surface.fetch("id"), surface] }
    adapters = @campaign.fetch("cases").filter_map do |row|
      [row, row.fetch("runtime_test")] if row.key?("runtime_test")
    end

    refute_empty adapters, "the campaign should have at least one executable case"
    assert adapters.any? { |row, _| row.fetch("id") == "RI-003" }, "RI-003 must remain executable"
    assert adapters.any? { |row, _| row.fetch("id") == "RI-011" }, "RI-011 must remain executable"

    adapters.each do |row, adapter|
      path = adapter.fetch("path")
      name = adapter.fetch("name")
      surface = surfaces.fetch(row.fetch("surface_id"))
      allowed_paths = surface.fetch("focused_test_paths") + surface.fetch("evidence_paths")

      refute path.start_with?("/"), "#{row.fetch("id")}: absolute runtime test path"
      refute path.split("/").include?(".."), "#{row.fetch("id")}: runtime test path escapes repository"
      assert_includes allowed_paths, path, "#{row.fetch("id")}: adapter path is not canonical"
      assert_match(/\Atest_[A-Za-z0-9_]+\z/, name, "#{row.fetch("id")}: invalid Minitest method name")

      source = File.read(File.join(ROOT, path), encoding: "UTF-8")
      runner = adapter.fetch("runner", "rails_minitest")
      case runner
      when "rails_minitest", "ruby_minitest"
        assert_match(/^\s*def\s+#{Regexp.escape(name)}(?:\s|\(|$)/, source,
                     "#{row.fetch("id")}: method #{name} is not defined in #{path}")
      when "node_test"
        assert_match(/(?:test|it)\s*\(\s*["'`]#{Regexp.escape(name)}["'`]/, source,
                     "#{row.fetch("id")}: exact Node test #{name} is not registered in #{path}")
        assert_match(/\bassert(?:\.|\s*\()/, source,
                     "#{row.fetch("id")}: Node adapter exposes no assertion in #{path}")
      else
        flunk "#{row.fetch("id")}: unsupported runtime test runner #{runner}"
      end
    end
  end

  def test_cases_without_runtime_adapters_remain_not_run
    @campaign.fetch("cases").reject { |row| row.key?("runtime_test") }.each do |row|
      assert_equal "NOT_RUN", row.fetch("runtime_status"), "#{row.fetch("id")}: no adapter may not imply execution"
      assert_nil row.fetch("runtime_evidence"), "#{row.fetch("id")}: no adapter may not carry invented evidence"
    end
  end

  def test_runtime_statuses_cannot_claim_pass_or_fail_without_saved_evidence
    @campaign.fetch("cases").each do |row|
      state = row.fetch("runtime_status")
      assert_includes VALID_RUNTIME_STATES, state, "#{row.fetch("id")}: unknown runtime state"

      next unless %w[PASS FAIL].include?(state)

      evidence = row.fetch("runtime_evidence").to_s.strip
      refute_empty evidence, "#{row.fetch("id")}: #{state} requires saved runtime evidence"
    end
  end

  def test_source_expectations_are_not_mislabeled_as_runtime_results
    @campaign.fetch("cases").each do |row|
      assert_equal "SOURCE_EXPECTATION_ONLY", row.fetch("assessment"), row.fetch("id")
    end

    @campaign.fetch("limitations").each do |limitation|
      refute_empty limitation.strip
    end
  end
end
