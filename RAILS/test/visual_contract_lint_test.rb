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

  # accent_on_prose read brgen's stylesheet directory, and brgen's bundle is not
  # that directory: _stack_brgen forwards eleven shared partials and
  # application.scss @uses more by bare name. A shared file painting accent on
  # prose landed in brgen unread. Assert the resolver reaches both halves, and
  # that it still reaches everything the old glob did.
  def test_the_accent_check_reads_brgens_whole_bundle
    sources = L.brgen_bundle_sources
    old_glob = Dir.glob(File.join(L::RAILS_ROOT, "brgen/{app,engines/*/app}/assets/stylesheets/**/*.scss"))

    assert_empty old_glob.map { |p| File.expand_path(p) } - sources,
                 "the resolver lost a file the directory glob had"
    assert_includes sources, File.expand_path(File.join(L::RAILS_ROOT, "shared/app/assets/stylesheets/_zen_shell.scss")),
                    "a partial _stack_brgen forwards must be in the bundle"
    assert_includes sources, File.expand_path(File.join(L::RAILS_ROOT, "shared/app/assets/stylesheets/_shell.scss")),
                    "a shared partial application.scss @uses by bare name must be in the bundle"
  end

  # _minimal.scss is the file that proves the resolver is following the bundle
  # rather than collecting every shared partial. _stack_brgen does not forward
  # it, so its `.price { color: var(--accent) }` reaches amber and bsdports and
  # never brgen — and accent_on_prose is a claim about brgen's grayscale
  # identity, not about the luxury or wscons dialects.
  def test_a_shared_partial_brgen_does_not_forward_is_not_in_its_bundle
    minimal = File.expand_path(File.join(L::RAILS_ROOT, "shared/app/assets/stylesheets/_minimal.scss"))

    assert_path_exists minimal
    refute_includes L.brgen_bundle_sources, minimal
  end

  # `.widget-empty a,\n.widget-cta {` is one selector, and the `a` in its first
  # member is what makes an accent on it correct. Reading only the line carrying
  # the brace made the check blind to every multi-line group in the tree.
  def test_the_selector_is_the_whole_group
    src = ".widget-empty a,\n.widget-cta {\n  color: var(--accent);\n}\n"
    selector = L.nearest_selector(src, 3)

    assert_includes selector, ".widget-empty a"
    assert_match L::INTERACTIVE_SELECTOR, selector
  end
end
