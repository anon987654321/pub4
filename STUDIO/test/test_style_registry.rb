# frozen_string_literal: true

require "minitest/autorun"
require_relative "../style_registry"

class StudioStyleRegistryTest < Minitest::Test
  def entry
    {
      "style_id" => "blue-hour", "version" => "1.0.0",
      "origin_class" => "hand_authored", "reference_hashes" => [], "modality" => "audio",
      "identity_locks" => ["soft_late_groove"], "controlled_variables" => ["tempo"],
      "scope_attributes" => { "groove_rhythm" => { "source" => nil, "strength" => 0.8 } },
      "negative_list" => ["alarm-like percussion"], "temporal_variation" => "none", "deprecation_target" => nil
    }
  end

  def test_checked_in_registry_resolves_all_modalities_to_same_version
    registry = Studio::StyleRegistry.load_registry
    %w[image prompt audio].each do |modality|
      resolved = Studio::StyleRegistry.resolve(style_id: "blue_hour", modality: modality, registry: registry)
      assert_equal "blue_hour", resolved["style_id"]
      assert_equal "1.0.0", resolved["version"]
      assert_equal modality, resolved["modality"]
    end
  end

  def test_registry_rejects_unknown_style_and_modality
    registry = Studio::StyleRegistry.load_registry
    assert_raises(Studio::StyleRegistry::InvalidStyle) do
      Studio::StyleRegistry.resolve(style_id: "missing", modality: "image", registry: registry)
    end
    assert_raises(Studio::StyleRegistry::InvalidStyle) do
      Studio::StyleRegistry.resolve(style_id: "blue_hour", modality: "video", registry: registry)
    end
  end

  def test_valid_entry_and_provenance
    manifest = { "lineage" => { "owner" => "operator" },
                 "influence" => { "value" => nil, "reason" => "hand authored" },
                 "negative_list_hash" => Studio::StyleRegistry.negative_list_hash(entry) }
    assert Studio::StyleRegistry.validate!(entry, manifest: manifest)
  end

  def test_rejects_missing_scope_strength
    bad = entry
    bad["scope_attributes"]["groove_rhythm"] = { "source" => nil }
    error = assert_raises(Studio::StyleRegistry::InvalidStyle) { Studio::StyleRegistry.validate!(bad) }
    assert_includes error.message, "strength"
  end

  def test_invalid_deprecation_date_is_rejected
    bad = entry.merge("deprecation_target" => "not-a-date")
    assert_raises(Studio::StyleRegistry::InvalidStyle) { Studio::StyleRegistry.validate!(bad) }
  end

  def test_rejects_unhashed_temporal_schedule
    bad = entry
    bad["temporal_variation"] = { "schedule_hash" => "not-a-hash" }
    assert_raises(Studio::StyleRegistry::InvalidStyle) { Studio::StyleRegistry.validate!(bad) }
  end

  def test_rejects_influence_without_metric_or_reason
    manifest = { "lineage" => {}, "influence" => { "value" => nil } }
    assert_raises(Studio::StyleRegistry::InvalidStyle) { Studio::StyleRegistry.validate!(entry, manifest: manifest) }
  end

  def test_mint_requires_newer_version_and_rationale
    previous = entry
    candidate = entry.merge("version" => "1.1.0")
    assert Studio::StyleRegistry.validate_mint!(previous: previous, candidate: candidate, owner: "operator", rationale: "tone curve changed")
    assert_raises(Studio::StyleRegistry::InvalidStyle) do
      Studio::StyleRegistry.validate_mint!(previous: previous, candidate: entry, owner: "operator", rationale: "same version")
    end
  end

  def test_refusal_happens_before_render_and_reports_match
    result = Studio::StyleRegistry.refuse!(
      proposal: { "percussion" => "alarm-like" },
      negative_list: ["alarm-like percussion"],
      matcher: ->(proposal, item) { proposal["percussion"] == "alarm-like" && item == "alarm-like percussion" }
    )
    assert_equal :refused, result[:status]
    assert_equal "STYLE_REFUSAL", result[:reason]
  end

  def test_refusal_requires_a_real_matcher
    assert_raises(ArgumentError) do
      Studio::StyleRegistry.refuse!(proposal: {}, negative_list: [], matcher: nil)
    end
  end
end
