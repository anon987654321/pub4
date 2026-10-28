# frozen_string_literal: true

require_relative "test_helper"
require "master"
require "yaml"
require_relative "../lib/fix/law_parity"
require_relative "../law/definition"

class TestLawParity < Minitest::Test
  def test_all_priority_constitutional_laws_have_explicit_evidence_modes
    parity = Master::Fix::LawParity.new
    laws = YAML.safe_load_file(Master::Fix::LawParity::LAWS_PATH, aliases: true)
    overlay = YAML.safe_load_file(File.join(File.dirname(Master::Fix::LawParity::LAWS_PATH), "law_enforcement.yml"), aliases: true)
    priority_ids = laws.filter_map do |id, spec|
      next unless spec.is_a?(Hash) && spec["tier"].to_s == "constitutional"
      next unless spec.key?("priority") && Integer(spec["priority"]) <= Master::Fix::LawParity::MAX_PRIORITY
      id
    end

    assert_equal 9, priority_ids.length
    assert priority_ids.all? { |id| Master::Fix::LawParity::COVERAGE_MODES.include?(overlay.dig(id, "coverage_mode")) }, parity.report
    assert_empty parity.call, parity.report
    assert_match(/RENDERED_VALUES=semantic/, parity.report)
  end

  def test_semantic_law_definition_is_not_counted_as_a_deterministic_detector
    parity = Master::Fix::LawParity.new
    assert_equal "semantic", YAML.safe_load_file(
      File.join(File.dirname(Master::Fix::LawParity::LAWS_PATH), "law_enforcement.yml"),
      aliases: true,
    ).dig("RENDERED_VALUES", "coverage_mode")
    refute_includes parity.send(:registered_detector_ids), "RENDERED_VALUES"
    assert_includes parity.send(:semantic_law_ids), "RENDERED_VALUES"
  end

  def test_priority_ceiling_covers_the_highest_current_constitutional_priority
    laws = YAML.safe_load_file(Master::Fix::LawParity::LAWS_PATH, aliases: true)
    overlay_path = File.join(File.dirname(Master::Fix::LawParity::LAWS_PATH), "law_enforcement.yml")
    overlay = YAML.safe_load_file(overlay_path, aliases: true) || {}
    priorities = laws.filter_map do |id, original|
      next unless original.is_a?(Hash)

      extra = overlay[id]
      spec = extra.is_a?(Hash) ? original.merge(extra) : original
      next unless spec["tier"].to_s == "constitutional" && spec.key?("priority")

      Integer(spec["priority"])
    end

    assert_operator priorities.length, :>, 0
    assert_operator priorities.max, :<=, Master::Fix::LawParity::MAX_PRIORITY,
                    "a new constitutional priority must not slip outside the LawParity audit ceiling"
  end

  def test_law_loader_errors_are_not_swallowed_as_an_empty_registry
    parity = Master::Fix::LawParity.new

    capture_io do
      ::Law.stub(:load_all, ->(*) { raise SyntaxError, "broken law fixture" }) do
        assert_raises(SyntaxError) { parity.send(:law_pack_ids) }
      end
    end
  end

  def test_orphaned_enforcement_overlay_entry_fails_instead_of_being_ignored
    Dir.mktmpdir("law-parity-orphan") do |dir|
      laws_path = File.join(dir, "laws.yml")
      File.write(laws_path, <<~YAML)
        VALID_CONSTITUTION:
          tier: constitutional
          priority: 1
          severity: error
          statement: a valid constitutional Law
      YAML
      File.write(File.join(dir, "law_enforcement.yml"), <<~YAML)
        ORPHAN_CONSTITUTION:
          enforcement: active
          coverage_mode: semantic
      YAML

      error = assert_raises(RuntimeError) do
        Master::Fix::LawParity.new(root: dir, laws_path:).send(:priority_constitutional_entries)
      end

      assert_match(/law_enforcement\.yml entry ORPHAN_CONSTITUTION does not resolve/, error.message)
    end
  end

  def test_unknown_enforcement_overlay_field_is_rejected
    Dir.mktmpdir("law-parity-unknown-field") do |dir|
      laws_path = File.join(dir, "laws.yml")
      File.write(laws_path, <<~YAML)
        VALID_CONSTITUTION:
          tier: constitutional
          priority: 1
          severity: error
          statement: a valid constitutional Law
      YAML
      File.write(File.join(dir, "law_enforcement.yml"), <<~YAML)
        VALID_CONSTITUTION:
          enforcement: active
          coverage_mode: semantic
          typo_coverage: semantic
      YAML

      error = assert_raises(RuntimeError) do
        Master::Fix::LawParity.new(root: dir, laws_path:).send(:priority_constitutional_entries)
      end

      assert_match(/unknown field\(s\): typo_coverage/, error.message)
    end
  end

  def test_report_ok_string_when_clean
    parity = Master::Fix::LawParity.new

    assert parity.ok?, parity.report
    assert_match(/law_parity: ok/, parity.report)
  end

  def test_empty_catalogue_is_not_reported_as_clean
    Dir.mktmpdir("law_parity") do |dir|
      path = File.join(dir, "laws.yml")
      File.write(path, "{}\n")

      error = assert_raises(RuntimeError) do
        Master::Fix::LawParity.new(root: dir, laws_path: path).call
      end
      assert_match(/non-empty mapping/, error.message)
    end
  end

  def test_deferred_without_expiry_is_gap
    dir = Dir.mktmpdir("law_parity")
    path = File.join(dir, "laws.yml")
    File.write(path, <<~YAML)
      ORPHAN_CONSTITUTIONAL:
        priority: 1
        tier: constitutional
        severity: error
        enforcement: deferred
        coverage_mode: deferred
        statement: missing expiry
    YAML
    gaps = Master::Fix::LawParity.new(root: dir, laws_path: path).call
    assert_equal 1, gaps.size
    assert_match(/deferred without expires_on|no detector/, gaps.first.reason)
  ensure
    FileUtils.remove_entry(dir) if dir && File.directory?(dir)
  end

  def test_active_with_detector_id_in_registry_passes
    parity = Master::Fix::LawParity.new
    data = YAML.safe_load_file(Master::Fix::LawParity::LAWS_PATH, aliases: true)
    # Enforcement metadata lives in the overlay that LawParity merges onto laws.yml.
    overlay = Master.load_yaml(File.join(Master::ROOT, "data", "law_enforcement.yml"))
    spec = data.fetch("CAPABILITY_STATUS_MUST_BE_TRUTHFUL").merge(overlay.fetch("CAPABILITY_STATUS_MUST_BE_TRUTHFUL"))
    assert_equal "active", spec["enforcement"]
    assert_includes Array(spec["detector_ids"]).map(&:to_s), "CAPABILITY_STATUS_MUST_BE_TRUTHFUL"
    refute parity.call.any? { |g| g.id == "CAPABILITY_STATUS_MUST_BE_TRUTHFUL" }
  end

  # Tag coverage is read from the detectors that carry the tag, so an umbrella
  # Law that no detector tags is a gap rather than a hardcoded pass.
  def test_tagged_coverage_needs_a_detector_that_carries_the_tag
    dir = Dir.mktmpdir("law_parity")
    path = File.join(dir, "laws.yml")
    File.write(path, <<~YAML)
      UNTAGGED_UMBRELLA:
        priority: 1
        tier: constitutional
        severity: error
        enforcement: active
        coverage: tagged_detectors
        coverage_mode: tagged
        statement: no detector tags this
    YAML
    gaps = Master::Fix::LawParity.new(root: dir, laws_path: path).call
    assert_equal ["UNTAGGED_UMBRELLA"], gaps.map(&:id)
  ensure
    FileUtils.remove_entry(dir) if dir && File.directory?(dir)
  end
end
