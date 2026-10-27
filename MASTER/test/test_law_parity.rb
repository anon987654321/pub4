# frozen_string_literal: true

require_relative "test_helper"
require "master"
require "yaml"
require_relative "../lib/fix/law_parity"

class TestLawParity < Minitest::Test
  # RENDERED_VALUES was the one uncovered priority Law; it has a definition under law/ now.
  def test_all_priority_constitutional_laws_are_audited
    parity = Master::Fix::LawParity.new

    assert_empty parity.call, parity.report
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


  def test_report_ok_string_when_clean
    parity = Master::Fix::LawParity.new
    assert_match(/law_parity: ok/, parity.report) if parity.ok?
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
