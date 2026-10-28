# frozen_string_literal: true

require_relative "test_helper"

class TestRuntimeCatalog < Minitest::Test
  def setup
    Master::Ground::RuntimeCatalog.clear_cache!
  end

  def test_load_all_sections
    assert_path_exists Master::Ground::RuntimeCatalog::CATALOG_PATH
    refute_path_exists File.join(Master::ROOT, "data", "runtime"), "runtime catalog must remain consolidated"

    sections = Master::Ground::RuntimeCatalog.sections

    assert_includes sections, "runtime", "web_boot_payload reads this section twice"
    assert_includes sections, "tts_phrases", "TtsController reads this section"

    sections.each do |section|
      data = Master::Ground::RuntimeCatalog.load(section)
      assert_kind_of Hash, data, "expected hash for #{section}"
      refute_empty data, "expected non-empty #{section}"
    end
  end

  def test_catalog_refreshes_after_same_process_edit
    Dir.mktmpdir("runtime_catalog_refresh") do |root|
      path = File.join(root, "runtime.yml")
      File.write(path, "probe:\n  marker: first\n")

      catalog = Master::Ground::RuntimeCatalog
      original_path = catalog.const_get(:CATALOG_PATH)
      catalog.send(:remove_const, :CATALOG_PATH)
      catalog.const_set(:CATALOG_PATH, path)

      begin
        catalog.clear_cache!
        assert_equal "first", catalog.load("probe").fetch("marker")

        File.write(path, "probe:\n  marker: second\n")

        assert_equal "second", catalog.load("probe").fetch("marker")
      ensure
        catalog.send(:remove_const, :CATALOG_PATH)
        catalog.const_set(:CATALOG_PATH, original_path)
        catalog.clear_cache!
      end
    end
  ensure
    Master::Ground::RuntimeCatalog.clear_cache!
  end

  def test_enhancements_filter_by_area_and_tier
    all = Master::Ground::RuntimeCatalog.enhancements
    assert all.size > 100

    face = Master::Ground::RuntimeCatalog.enhancements(area: "face")
    assert face.all? { |item| item["area"] == "face" }

    p0 = Master::Ground::RuntimeCatalog.enhancements(tier: "p0")
    assert p0.all? { |item| item["tier"] == "p0" }
    assert p0.any? { |item| item["status"] == "implemented" }
  end

  def test_micro_interactions_count_and_lookup
    items = Master::Ground::RuntimeCatalog.micro_interactions
    assert_equal 80, items.size

    entry = Master::Ground::RuntimeCatalog.micro_interaction("mi_042")
    assert_equal "escape emits user:interrupt", entry["summary"]
  end

  def test_web_boot_payload_shape
    payload = Master::Ground::RuntimeCatalog.web_boot_payload

    assert_equal "/runtime/topologies", payload[:topologies_path]
    assert payload[:enhancements_pending_count].is_a?(Integer)
    assert payload[:micro_interactions].is_a?(Array)
    assert payload[:event_registry].is_a?(Hash)
    assert payload[:visual_limits].is_a?(Hash)
    assert payload[:tts_config].is_a?(Hash)
    assert payload[:topologies].is_a?(Hash)
  end

  def test_web_boot_payload_minimal_shape
    payload = Master::Ground::RuntimeCatalog.web_boot_payload_minimal

    assert_equal "/runtime/topologies", payload[:topologies_path]
    assert_equal "/runtime/config", payload[:config_path]
    assert payload[:enhancements_pending_count].is_a?(Integer)
    assert payload[:enhancements].is_a?(Array)
    # The payload's contract is that it reports a real aesthetic, not a
    # particular one, so the house default can change without this going red.
    assert_includes Master::Voice::Aesthetic::MODES, payload[:aesthetic]
    refute payload.key?(:topologies)
  end

  # Through `load`, the one documented door: the sections and the shape they
  # promise are the contract, not a named reader per section.
  def test_invariants_and_event_registry
    inv = Master::Ground::RuntimeCatalog.load("invariants")
    assert inv["invariants"].is_a?(Array)
    assert inv["anti_patterns"].is_a?(Array)

    registry = Master::Ground::RuntimeCatalog.load("event_registry")
    assert registry["namespaces"].is_a?(Array)
    assert registry["established_events"].is_a?(Array)
  end
end
