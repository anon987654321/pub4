# frozen_string_literal: true

require "json"
require "minitest/autorun"

class InteractionCampaignContractTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  MANIFEST = File.join(__dir__, "interaction_campaign_400.json")
  REQUIRED_CASE_FIELDS = %w[
    id surface_id surface actor precondition action fault_mode fault_injection
    expected evidence_paths assessment runtime_status
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

  def test_every_surface_has_exactly_twenty_cases
    surfaces = @campaign.fetch("surfaces")
    known_ids = surfaces.map { |surface| surface.fetch("id") }
    actual = @campaign.fetch("cases").group_by { |row| row.fetch("surface_id") }
    expected = known_ids.to_h { |surface_id| [surface_id, 20] }

    assert_equal expected.sort, actual.transform_values(&:length).sort
    surfaces.each do |surface|
      rows = actual.fetch(surface.fetch("id"))
      assert rows.all? { |row| row.fetch("surface") == surface.fetch("name") },
             "#{surface.fetch("id")}: case surface names have drifted"
    end
  end

  def test_each_surface_covers_all_twenty_fault_modes_once
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

  def test_every_case_has_an_actionable_oracle_and_required_fields
    @campaign.fetch("cases").each do |row|
      missing = REQUIRED_CASE_FIELDS.reject { |field| row.key?(field) }
      assert_empty missing, "#{row["id"]}: missing fields #{missing.join(", ")}"

      %w[actor precondition action fault_injection expected].each do |field|
        refute_empty row.fetch(field).to_s.strip, "#{row["id"]}: #{field} is blank"
      end
      refute_empty row.fetch("evidence_paths"), "#{row["id"]}: no evidence paths"
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

    @campaign.fetch("cases").each do |row|
      row.fetch("evidence_paths").each do |relative|
        assert File.file?(File.join(ROOT, relative)), "#{row.fetch("id")}: missing #{relative}"
      end
    end
  end

  def test_runtime_statuses_cannot_claim_pass_without_execution_evidence
    @campaign.fetch("cases").each do |row|
      state = row.fetch("runtime_status")
      assert_includes VALID_RUNTIME_STATES, state, "#{row.fetch("id")}: unknown runtime state"

      next unless %w[PASS FAIL].include?(state)

      evidence = row["runtime_evidence"].to_s.strip
      refute_empty evidence, "#{row.fetch("id")}: #{state} requires saved runtime evidence"
    end
  end

  def test_source_expectations_are_not_mislabeled_as_runtime_results
    @campaign.fetch("cases").each do |row|
      assert_equal "SOURCE_EXPECTATION_ONLY", row.fetch("assessment"), row.fetch("id")
      refute_empty row.fetch("expected").to_s
    end
  end
end
