# frozen_string_literal: true

require_relative "test_helper"
require "master"
require_relative "../lib/fix/law_parity"

class TestLawParity < Minitest::Test
  def test_priority_constitutional_laws_are_covered_or_deferred
    parity = Master::Fix::LawParity.new
    gaps = parity.call
    assert_empty gaps, parity.report
  end

  def test_report_ok_string_when_clean
    parity = Master::Fix::LawParity.new
    assert_match(/law_parity: ok/, parity.report) if parity.ok?
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
        statement: no detector tags this
    YAML
    gaps = Master::Fix::LawParity.new(root: dir, laws_path: path).call
    assert_equal ["UNTAGGED_UMBRELLA"], gaps.map(&:id)
  ensure
    FileUtils.remove_entry(dir) if dir && File.directory?(dir)
  end
end
