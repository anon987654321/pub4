# frozen_string_literal: true

require "minitest/autorun"
require "ripper"
require "yaml"

class LayoutCheckEnforcementContractTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  LAWS = File.join(ROOT, "MASTER/data/laws.yml")
  SURFACE_LAWS = File.join(ROOT, "MASTER/law/detectors/surface_laws.rb")
  LAYOUT_SUITE = File.join(ROOT, "MASTER/checks/lib/layout_suite.rb")
  CHECKS = File.join(ROOT, "MASTER/checks/checks.yml")
  MINIMAL_ENDGAME = File.join(ROOT, "RAILS/__shared/app/assets/stylesheets/_surface_chrome_endgame.scss")
  BRGEN_OVERRIDES = File.join(ROOT, "RAILS/brgen/app/assets/stylesheets/_brgen_shared_overrides.scss")
  AMBER_OVERRIDES = File.join(ROOT, "RAILS/amber/app/assets/stylesheets/_amber_shared_overrides.scss")
  BSDPORTS_APP = File.join(ROOT, "RAILS/bsdports/app/assets/stylesheets/application.scss")

  def test_core_grid_and_typography_principles_resolve_to_executable_laws
    data = YAML.safe_load_file(LAWS, aliases: true)

    {
      "grid_based_layouts" => %w[GRID_STRUCTURE EIGHT_PX_RHYTHM],
      "grid_systems" => %w[GRID_STRUCTURE EIGHT_PX_RHYTHM],
      "typography_hierarchy" => %w[TYPE_HIERARCHY TYPE_TITLE_TOKEN],
      "aesthetic_integrity" => %w[AESTHETIC_MINIMALISM NO_EYEBROW_LABEL TYPE_HIERARCHY],
      "clean_lines" => %w[NO_DECORATIVE_FX AESTHETIC_MINIMALISM NO_EYEBROW_LABEL],
      "content_prioritized" => %w[AESTHETIC_MINIMALISM NO_EYEBROW_LABEL TYPE_HIERARCHY],
      "essential_elements_only" => %w[AESTHETIC_MINIMALISM NO_EYEBROW_LABEL],
      "minimal_materials" => %w[AESTHETIC_MINIMALISM NO_DECORATIVE_FX],
      "remove_non_essentials" => %w[AESTHETIC_MINIMALISM NO_EYEBROW_LABEL],
      "visual_hierarchy_clarity" => %w[TYPE_HIERARCHY NO_EYEBROW_LABEL],
    }.each do |name, law_ids|
      entry = find_entry(data, name)
      refute_nil entry, "missing declared design principle #{name}"
      assert_equal "covered", entry["status"], "#{name} is still a prose-only gap"
      law_ids.each { |law_id| assert_includes Array(entry["law_ids"]), law_id, "#{name} does not map to #{law_id}" }
    end

    source = File.read(SURFACE_LAWS, encoding: "UTF-8")
    assert Ripper.sexp(source), "surface laws must remain valid Ruby"
    assert_includes source, "LawDSL.law :GRID_STRUCTURE"
    assert_includes source, "grid-like direct children use absolute offsets and a fixed wide width"
  end

  def test_layout_suite_requires_rendered_measurements_not_only_source_checks
    source = File.read(LAYOUT_SUITE, encoding: "UTF-8")
    registry = YAML.safe_load_file(CHECKS, aliases: true)

    assert_includes source, 'require_relative "rendered_suite"'
    assert_includes source, "RenderedSuiteCheck"
    assert_includes source, "require_rendered_evidence!"
    assert_includes source, "inconclusive item(s)"
    assert_includes source, "unapproved visual finding(s)"
    assert_equal "layout_suite", registry.dig("rendered_suite", "covered_by")
  end

  def test_ultra_minimal_contract_is_the_last_dialect_pass
    source = File.read(MINIMAL_ENDGAME, encoding: "UTF-8")

    assert_includes source, "@mixin ultra_minimal"
    assert_equal 3, source.scan("@include ultra_minimal;").size
    assert_includes source, "font-size: clamp(2rem, 5vw, 3.25rem);"
    assert_includes source, "font-weight: var(--weight-heavy);"
    assert_includes source, "text-transform: none;"
    assert_match(/main#main-content :is\(h2, h3, h4, h5, h6(?:,|\))/, source)
    assert_includes source, "font-size: var(--text-lg);"
    assert_includes source, "border: 0;"
    assert_includes source, "body.wscons .tabs .active"
    assert_includes source, "Content boundaries come from placement and whitespace"
    assert_includes source, "main#main-content :where("
    assert_includes source, "box-shadow: none;"
    assert_includes source, "main#main-content .amber-editorial-nav a"
    %w[.feed-post .match .organize-tip .brand .amber-look .amber-editorial-nav .post-show-actions .port-row].each do |selector|
      assert_includes source, selector, "minimal chrome must cover #{selector}"
    end

    # Ultra-minimalism removes decorative rules, not functional controls or
    # visible keyboard affordances.
    assert_includes source, "main#main-content :is(input, select, textarea)"
    # Text fields are borderless; keyboard focus is the shared outline ring.
    assert_includes source, ":focus-visible { border: 0; outline: var(--focus-ring); outline-offset: 2px; }"
    assert_includes source, "body.wscons :is(input, select, textarea, button, .btn):focus-visible"

    assert_includes File.read(BRGEN_OVERRIDES, encoding: "UTF-8"), "@include endgame.brgen;"
    assert_includes File.read(AMBER_OVERRIDES, encoding: "UTF-8"), "@include endgame.amber;"
    assert_includes File.read(BSDPORTS_APP, encoding: "UTF-8"), "@include endgame.bsdports;"
  end

  def test_auto_repeat_tile_grids_can_shrink_below_their_preferred_tile_width
    unsafe = /grid-template-columns\s*:\s*repeat\(\s*auto-(?:fill|fit)\s*,\s*minmax\(\s*(?!min\()\s*(?:var\(\s*--[\w-]+\s*\)|\d+(?:\.\d+)?(?:px|rem|em|ch))\s*,\s*1fr\s*\)/i
    sheets = Dir.glob(File.join(ROOT, "RAILS", "**", "app/assets/stylesheets", "**", "*.{scss,css}"))
    violations = sheets.reject { |sheet_path| sheet_path.match?(%r{/(?:builds|vendor|node_modules)/}) }
                       .flat_map do |sheet_path|
      source = File.read(sheet_path, encoding: "UTF-8")
                   .gsub(%r{/\*.*?\*/}m, "")
                   .gsub(%r{//[^\n]*}, "")
      source.to_enum(:scan, unsafe).map do
        line = source[0...Regexp.last_match.begin(0)].count("\n") + 1
        "#{sheet_path.delete_prefix("#{ROOT}/")}:#{line}"
      end
    end

    assert_empty violations,
                 "auto-repeat tracks must cap the preferred tile width at the available container width:\n  #{violations.join("\n  ")}"
  end

  private

  def find_entry(value, name)
    case value
    when Hash
      return value[name] if value[name].is_a?(Hash)

      value.each_value do |child|
        found = find_entry(child, name)
        return found if found
      end
    when Array
      value.each do |child|
        found = find_entry(child, name)
        return found if found
      end
    end
    nil
  end
end
