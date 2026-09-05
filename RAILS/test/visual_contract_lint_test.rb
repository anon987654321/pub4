# frozen_string_literal: true

require "minitest/autorun"
require_relative "../shared/lib/pub4/visual_contract_lint"
require_relative "../shared/lib/pub4/master_design"

class VisualContractLintTest < Minitest::Test
  L = Pub4::VisualContractLint
  SOURCE = File.expand_path("../shared/lib/pub4/visual_contract_lint.rb", __dir__)

  def test_text_contrast_min_reads_large_text_contrast
    law = Pub4::MasterDesign.dig("typography", "accessibility", "large_text_contrast")
    refute_nil law, "typography.accessibility.large_text_contrast is gone from rules.yml"
    assert_in_delta law.to_f, L.text_contrast_min, 0.01
  end

  # minitest/mock is unavailable to these bare-ruby tests. The override is the
  # proof the floor is not a literal 4.5: a hardcoded copy would ignore this.
  def test_the_floor_tracks_the_yaml_key
    meta = L.singleton_class
    meta.send(:alias_method, :__real_accessibility_rules, :accessibility_rules)
    L.define_singleton_method(:accessibility_rules) { { "large_text_contrast" => 8.25 } }
    assert_in_delta 8.25, L.text_contrast_min, 0.01
  ensure
    meta.send(:remove_method, :accessibility_rules)
    meta.send(:alias_method, :accessibility_rules, :__real_accessibility_rules)
    meta.send(:remove_method, :__real_accessibility_rules)
  end

  def test_the_source_names_the_yaml_key
    source = File.read(SOURCE, encoding: "UTF-8")
    assert_includes source, "large_text_contrast"
    assert_includes source, "MasterDesign"
  end
end
