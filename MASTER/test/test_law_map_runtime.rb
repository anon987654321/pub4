# frozen_string_literal: true

require_relative "test_helper"

class TestLawMapRuntime < Minitest::Test
  def setup
    @root = Master::ROOT
  end

  def test_law_map_loads
    map = Master::Ground::Map::LawMap.load(root: @root)
    assert map.laws.size > 50, "expected substantial law map"
    assert map.summary_line.include?("law_map")
    assert map.aesthetic.any?, "aesthetic/ui cluster should be non-empty"
  end

  def test_law_map_reports_unmapped_concepts_instead_of_hiding_them
    map = Master::Ground::Map::LawMap.load(root: @root)

    assert_equal ["no_privilege_escalation"], map.unmapped.keys
    assert_match(/1 unmapped/, map.summary_line)
  end

  def test_mode_posture_defaults_and_set
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "data"))
      File.write(File.join(dir, "data", "limits.yml"), <<~YAML)
        session_modes:
          default: balanced
          modes:
            loose: {scan_profile: cosmetic, council: false, autofix_llm: false, autofix_mechanical: true, max_fix_passes: 3}
            balanced: {scan_profile: full, council: risky, autofix_llm: true, autofix_mechanical: true, max_fix_passes: 8}
            strict: {scan_profile: full, council: true, autofix_llm: true, autofix_mechanical: true, max_fix_passes: 15}
      YAML
      ENV.delete("MASTER_MODE")
      posture = Master::Ground::ModePosture.new(root: dir)
      assert_equal "balanced", posture.current[:name]
      posture.set!("strict")
      assert_equal "strict", posture.current[:name]
      assert_equal 15, posture.current[:max_fix_passes]
    end
  ensure
    ENV.delete("MASTER_MODE")
  end

  def test_design_thresholds_touch_min
    min = Master::Design::Thresholds.touch_min_px(root: @root)
    assert_operator min, :>=, 44
  end

  def test_layout_rules_and_pixel_perfection_share_one_spacing_list
    design = Master.tokens(root: @root)
    grid = design.dig("layout_rules", "grid", "allowed_spacing_px")
    rhythm = design.dig("pixel_perfection", "eight_px_rhythm")
    fitts = design.dig("ux_laws", "fitts", "target_min_px")
    touch = design.dig("layout_rules", "touch", "target_min_px")

    assert_equal grid, rhythm
    assert_equal touch, fitts
    assert_equal 44, touch
  end

  def test_design_law_configuration_is_present_in_the_canonical_token_map
    design = Master.tokens(root: @root)
    %w[layout_rules kinetic_depth visual_design motion_and_sound data_visualization automated_css_analysis ux_laws worn_type pixel_perfection rams_checklist ui_polish pwa].each do |key|
      assert_kind_of Hash, design[key], "missing canonical design block #{key}"
    end
    assert_equal design.dig("scale", "space_px"), design.dig("layout_rules", "grid", "allowed_spacing_px")
    assert_equal design.dig("scale", "space_px"), design.dig("pixel_perfection", "eight_px_rhythm")
    assert_equal design.dig("layout_rules", "touch", "target_min_px"), design.dig("ux_laws", "fitts", "target_min_px")
  end

  def test_laws_register
    require_relative "../lib/review/scan/law_tree"
    ids = Master::Review::Scan::LawTree.ids.map(&:upcase)
    %w[NO_DECORATIVE_FX FLAT_PIXELS TOUCH_TARGET_MIN EIGHT_PX_RHYTHM RAMS_HONEST].each do |id|
      assert_includes ids, id, "missing aesthetic law #{id}"
    end
  end

  def test_scan_path_aliases
    req = Master::CLI::Scan::Request.allocate
    req.instance_variable_set(:@scanner, nil)
    req.instance_variable_set(:@root, Master::ROOT)
    req.instance_variable_set(:@arg, "face")
    req.instance_variable_set(:@depth, :deep)
    target = req.send(:expand_scan_target, "rails")
    assert_equal Master::RAILS_ROOT, target
    face = req.send(:expand_scan_target, "face")
    assert face.end_with?("master/public")
  end

  def test_provenance_gaps_flags_entries_missing_source
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "data"))
      File.write(File.join(dir, "data", "laws.yml"), <<~YAML)
        law_map:
          schema: 1
          laws:
            attributed_one:
              meaning: has a reason
              severity: high
              confidence: 0.8
              operation: fix
              law_ids: []
              status: gap
              tags: []
              source: added after incident
            unattributed_one:
              meaning: no reason given
              severity: high
              confidence: 0.8
              operation: fix
              law_ids: []
              status: gap
              tags: []
      YAML

      map = Master::Ground::Map::LawMap.load(root: dir)
      gaps = map.provenance_gaps

      assert_equal ["unattributed_one"], gaps.map(&:id)
    end
  end

  def test_corrupt_law_map_does_not_become_an_empty_registry
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "data"))
      File.write(File.join(dir, "data", "laws.yml"), "law_map: [broken")

      error = assert_raises(RuntimeError) { Master::Ground::Map::LawMap.load(root: dir) }

      assert_match(/laws.yml/, error.message)
    end
  end

  def test_law_map_metadata_and_detector_names_are_coherent
    map = Master::Ground::Map::LawMap.load(root: @root)

    feature_envy = map["avoid_feature_envy"]
    assert_equal "feature_envy", feature_envy.detects
    assert_equal ["FEATURE_ENVY"], feature_envy.law_ids

    security = map["security"]
    assert_equal "plaintext_secrets", security.detects
    assert_equal "critical", security.severity
    assert_includes security.meaning, "source literals"
    refute_empty security.operation

    refute map.laws.key?("fittss_law"), "a misspelled duplicate Fitts entry must not survive"
    assert_empty map.integrity, "invalid map metadata must not be treated as a clean mapping"
  end

  def test_law_map_integrity_checks_the_combined_executable_and_scanner_population
    require_relative "../lib/review/scan/law_tree"
    map = Master::Ground::Map::LawMap.load(root: @root)
    registered = Master::Review::Scan::LawTree.ids.map(&:upcase)
    require_relative "../law/definition"
    ::Law.load_all(File.expand_path("../law", __dir__)) if ::Law.definitions.empty?
    executable = ::Law.definitions.keys.map { |id| id.to_s.upcase }
    declared = Master.law_entries(root: @root).map { |rule| rule["id"].to_s.upcase }

    findings = map.integrity(registered_law_ids: registered | declared | executable)
    assert map.covered.any?
    assert_empty findings, "law-map integrity findings: #{findings.join('; ')}"
  end

  def test_integrity_skips_reference_checks_only_when_registry_is_omitted
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "data"))
      File.write(File.join(dir, "data", "laws.yml"), <<~YAML)
        law_map:
          schema: 1
          laws:
            sample:
              meaning: a mapped concept
              detects: sample_detector
              severity: medium
              confidence: 0.8
              operation: fix
              law_ids: [KNOWN_RULE]
              status: covered
              tags: [code]
      YAML
      map = Master::Ground::Map::LawMap.load(root: dir)

      assert_empty map.integrity
      assert_includes map.integrity(registered_law_ids: []), "law sample maps to unknown law KNOWN_RULE"
    end
  end

  def test_integrity_rejects_invalid_status_severity_confidence_and_empty_metadata
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "data"))
      File.write(File.join(dir, "data", "laws.yml"), <<~YAML)
        law_map:
          schema: 1
          laws:
            sample:
              meaning:
              detects:
              severity: urgent
              confidence: "high"
              operation:
              law_ids: []
              status: maybe
              tags: [code]
      YAML
      findings = Master::Ground::Map::LawMap.load(root: dir).integrity

      assert_includes findings, 'law sample has invalid status "maybe"'
      assert_includes findings, 'law sample has invalid severity "urgent"'
      assert_includes findings, 'law sample has invalid confidence "high"'
      assert_includes findings, "law sample has no meaning"
      assert_includes findings, "law sample has no detector description"
      assert_includes findings, "law sample has no repair operation"
    end
  end

  def test_integrity_enforces_the_coverage_status_and_reference_relationship
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "data"))
      File.write(File.join(dir, "data", "laws.yml"), <<~YAML)
        law_map:
          schema: 1
          laws:
            covered_without_id:
              meaning: missing implementation
              detects: missing_detector
              severity: high
              confidence: 0.8
              operation: fix
              law_ids: []
              status: covered
              tags: [code]
            gap_with_id:
              meaning: unimplemented concept
              detects: future_detector
              severity: medium
              confidence: 0.6
              operation: implement
              law_ids: [GAP_RULE]
              status: gap
              tags: [code]
            unmapped_with_id:
              meaning: unmapped concept
              detects: unknown_detector
              severity: low
              confidence: 0.5
              operation: investigate
              law_ids: [UNMAPPED_RULE]
              status: unmapped
              tags: [code]
      YAML

      findings = Master::Ground::Map::LawMap.load(root: dir).integrity

      assert_includes findings, "covered law covered_without_id has no law_ids"
      assert_includes findings, "gap law gap_with_id must not claim law_ids"
      assert_includes findings, "unmapped law unmapped_with_id must not claim law_ids"
    end
  end

  def test_integrity_rejects_duplicate_law_ids
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "data"))
      File.write(File.join(dir, "data", "laws.yml"), <<~YAML)
        law_map:
          schema: 1
          laws:
            duplicated:
              meaning: one mapping, one reference per rule
              detects: duplicate_detector
              severity: medium
              confidence: 0.7
              operation: fix
              law_ids: [SAME_RULE, SAME_RULE]
              status: covered
              tags: [code]
      YAML

      findings = Master::Ground::Map::LawMap.load(root: dir).integrity

      assert_includes findings, "law duplicated repeats law_ids: SAME_RULE"
    end
  end
end
