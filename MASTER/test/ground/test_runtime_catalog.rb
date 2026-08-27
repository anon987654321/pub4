# frozen_string_literal: true

require_relative "../test_helper"

class TestRuntimeCatalog < Minitest::Test
  def setup
    Master::Ground::RuntimeCatalog.clear_cache!
  end

  def test_load_all_sections
    assert_path_exists Master::Ground::RuntimeCatalog::CATALOG_PATH
    refute_path_exists File.join(Master::ROOT, "data", "runtime"), "runtime catalog must remain consolidated"

    Master::Ground::RuntimeCatalog::SECTIONS.each do |section|
      data = Master::Ground::RuntimeCatalog.load(section)
      assert_kind_of Hash, data, "expected hash for #{section}"
      refute_empty data, "expected non-empty #{section}"
    end
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
    # Was %w[wscons phosphor], which pinned the retro modes as the only legal
    # answers — so this went red the moment brutalist became the house default
    # in 02e798aca and stayed red, unnoticed, because test/lib/** is outside
    # `rake test`'s flat glob. Assert against MODES: the payload's contract is
    # that it reports a real aesthetic, not that it reports a particular one.
    assert_includes Master::Voice::Aesthetic::MODES, payload[:aesthetic]
    refute payload.key?(:topologies)
  end

  def test_invariants_and_event_registry
    inv = Master::Ground::RuntimeCatalog.invariants
    assert inv["invariants"].is_a?(Array)
    assert inv["anti_patterns"].is_a?(Array)

    registry = Master::Ground::RuntimeCatalog.event_registry
    assert registry["namespaces"].is_a?(Array)
    assert registry["established_events"].is_a?(Array)
  end

  def test_face3d_migration_steps
    migration = Master::Ground::RuntimeCatalog.face3d_migration
    assert migration["migration_steps"].is_a?(Array)
    assert migration["blendshape_mapping"].is_a?(Array)
    assert migration["modules"].is_a?(Array)
  end
end
