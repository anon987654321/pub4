# frozen_string_literal: true

require_relative "test_helper"

class TestPrincipleMapRuntime < Minitest::Test
  def setup
    @root = Master::ROOT
  end

  def test_principle_map_loads
    map = Master::Ground::Map::Principle.load(root: @root)
    assert map.principles.size > 50, "expected substantial principle map"
    assert map.summary_line.include?("principle_map")
    assert map.aesthetic.any?, "aesthetic/ui cluster should be non-empty"
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
    design = Master.design_rules(root: @root)
    grid = design.dig("layout_rules", "grid", "allowed_spacing_px")
    rhythm = design.dig("pixel_perfection", "eight_px_rhythm")
    fitts = design.dig("ux_laws", "fitts", "target_min_px")
    touch = design.dig("layout_rules", "touch", "target_min_px")

    assert_equal grid, rhythm
    assert_equal touch, fitts
    assert_equal 44, touch
  end

  def test_aesthetic_rules_register
    require_relative "../lib/review/scan/rule_dsl"
    ids = Master::Review::Scan::Rule.registry.filter_map do |k|
      begin
        k.auto_build? ? k.new.id.to_s.upcase : nil
      rescue StandardError # scan: intentional — non-buildable rules have no id; nil is the census answer
        nil
      end
    end
    %w[NO_DECORATIVE_FX FLAT_PIXELS TOUCH_TARGET_MIN EIGHT_PX_RHYTHM RAMS_HONEST].each do |id|
      assert_includes ids, id, "missing aesthetic rule #{id}"
    end
  end

  def test_scan_path_aliases
    req = Master::CLI::ScanRequest.allocate
    req.instance_variable_set(:@scanner, nil)
    req.instance_variable_set(:@root, Master::ROOT)
    req.instance_variable_set(:@arg, "face")
    req.instance_variable_set(:@depth, :deep)
    target = req.send(:expand_scan_target, "rails")
    assert_equal Master::RAILS_ROOT, target
    face = req.send(:expand_scan_target, "face")
    assert face.end_with?("web/public")
  end

  def test_bias_guard_detects_aesthetic_neglect
    guard = Master::Ground::BiasGuard.new(root: @root)
    proposal = Struct.new(:action, :reason, :confidence).new("edit view", "update erb scss layout", 0.9)
    hits = guard.detect(proposal)
    assert_includes hits, "aesthetic_neglect"
  end

  # Advisory-only (see Map::Principle#provenance_gaps) -- must never be wired
  # into SelfTest, so a real fixture with a mix of attributed/unattributed
  # entries confirms it just reports, it doesn't gate anything.
  def test_provenance_gaps_flags_entries_missing_source
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "data"))
      File.write(File.join(dir, "data", "principle_map.yml"), <<~YAML)
        principles:
          attributed_one:
            meaning: has a reason
            severity: high
            confidence: 0.8
            operation: fix
            rule_ids: []
            status: gap
            tags: []
            source: added 2026-01-01 after incident #42
          unattributed_one:
            meaning: no reason given
            severity: high
            confidence: 0.8
            operation: fix
            rule_ids: []
            status: gap
            tags: []
      YAML

      map = Master::Ground::Map::Principle.load(root: dir)
      gaps = map.provenance_gaps

      assert_equal ["unattributed_one"], gaps.map(&:id)
    end
  end

  def test_principle_map_integrity_against_registry
    require_relative "../lib/review/scan/rule_dsl"
    map = Master::Ground::Map::Principle.load(root: @root)
    registered = Master::Review::Scan::Rule.registry.filter_map do |k|
      begin
        k.auto_build? ? k.new.id.to_s : nil
      rescue StandardError # scan: intentional — non-buildable rules have no id; nil is the census answer
        nil
      end
    end
    findings = map.integrity(registered_rule_ids: registered)
    assert map.covered.any?
    assert_operator findings.size, :<, map.principles.size
  end
end
