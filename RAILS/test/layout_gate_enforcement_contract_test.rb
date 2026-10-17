# frozen_string_literal: true

require "minitest/autorun"
require "ripper"
require "yaml"

class LayoutGateEnforcementContractTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  LAWS = File.join(ROOT, "MASTER/data/laws.yml")
  SURFACE_LAWS = File.join(ROOT, "MASTER/lib/review/scan/laws/surface_laws.rb")
  LAYOUT_SUITE = File.join(ROOT, "MASTER/gates/lib/layout_suite.rb")
  GATES = File.join(ROOT, "MASTER/gates/gates.yml")

  def test_core_grid_and_typography_principles_resolve_to_executable_laws
    data = YAML.safe_load_file(LAWS, aliases: true)

    {
      "grid_based_layouts" => %w[GRID_STRUCTURE EIGHT_PX_RHYTHM],
      "grid_systems" => %w[GRID_STRUCTURE EIGHT_PX_RHYTHM],
      "typography_hierarchy" => %w[TYPE_HIERARCHY TYPE_TITLE_TOKEN],
    }.each do |name, law_ids|
      entry = find_entry(data, name)
      refute_nil entry, "missing declared design principle #{name}"
      assert_equal "covered", entry["status"], "#{name} is still a prose-only gap"
      law_ids.each { |law_id| assert_includes Array(entry["law_ids"]), law_id, "#{name} does not map to #{law_id}" }
    end

    source = File.read(SURFACE_LAWS, encoding: "UTF-8")
    assert Ripper.sexp(source), "surface laws must remain valid Ruby"
    assert_includes source, "LawDSL.law :GRID_STRUCTURE"
    assert_includes source, "direct-child layout uses absolute offsets and a fixed wide width"
  end

  def test_layout_suite_requires_rendered_measurements_not_only_source_checks
    source = File.read(LAYOUT_SUITE, encoding: "UTF-8")
    registry = YAML.safe_load_file(GATES, aliases: true)

    assert_includes source, 'require_relative "rendered_suite"'
    assert_includes source, "RenderedSuiteGate"
    assert_includes source, "require_rendered_evidence!"
    assert_includes source, "inconclusive item(s)"
    assert_includes source, "unapproved visual finding(s)"
    assert_equal "layout_suite", registry.dig("rendered_suite", "covered_by")
  end

  def test_auto_repeat_tile_grids_can_shrink_below_their_preferred_tile_width
    unsafe = /grid-template-columns\s*:\s*repeat\(\s*auto-(?:fill|fit)\s*,\s*minmax\(\s*var\(\s*--tile-min-[\w-]+\s*\)\s*,\s*1fr\s*\)/i
    archived = %w[
      _layout_micro_refinements.scss
      _surface_micro_refinements.scss
      _surface_micro_refinements_two.scss
    ]

    sheets = Dir.glob(File.join(ROOT, "RAILS", "**", "app/assets/stylesheets", "**", "*.{scss,css}"))
    violations = sheets.reject { |sheet_path| archived.include?(File.basename(sheet_path)) }
                       .reject { |sheet_path| sheet_path.match?(%r{/(?:builds|vendor|node_modules)/}) }
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
