# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require_relative "../../gates/support/design_metrics"
require_relative "../../gates/support/geometry_autofix"
require_relative "../../gates/lib/meta/gate_mutation"
require_relative "../../gates/lib/rendered/layout_snapshot"
require_relative "../../gates/support/geometry_probe"
require_relative "../../gates/support/geometry_type"
require_relative "../../../OPENBSD/lib/gate_result"

# Unit coverage for the pure logic behind the browser-backed gates. Nothing
# here launches Chrome or needs a booted app — the CDP-dependent paths are
# exercised by running the gates themselves.
class RenderedGatesTest < Minitest::Test
  M = Deploy::DesignMetrics

  # --- token contrast cross-product ---------------------------------------

  def test_token_pairs_matches_light_and_dark_modes_separately
    dialect = {
      "light_text" => "#000000", "light_bg" => "#ffffff",
      "dark_text" => "#ffffff", "dark_bg" => "#000000",
    }
    labels = M.token_pairs("luxury", dialect).map { |p| p[:label] }
    assert_includes labels, "luxury.light_text/light_bg"
    assert_includes labels, "luxury.dark_text/dark_bg"
    refute_includes labels, "luxury.light_text/dark_bg",
                    "a light-mode foreground must never be paired with a dark-mode background"
  end

  def test_token_pairs_covers_accent_not_just_text
    dialect = { "text" => "#d8d6e0", "accent" => "#7c6fd6", "bg" => "#17161c" }
    labels = M.token_pairs("social", dialect).map { |p| p[:label] }
    assert_includes labels, "social.accent/bg",
                    "accent is used as a text colour and must be in the enumerated space"
  end

  def test_suggest_contrast_fix_reaches_target_on_dark_background
    fix = M.suggest_contrast_fix("#7c6fd6", "#17161c", 4.5)
    refute_nil fix
    assert fix[:ratio] >= 4.5, "suggestion must actually clear the target, got #{fix[:ratio]}"
    assert_match(/\A#[0-9a-f]{6}\z/, fix[:hex])
  end

  def test_suggest_contrast_fix_lightens_on_dark_and_darkens_on_light
    on_dark = M.suggest_contrast_fix("#7c6fd6", "#000000", 7.0)
    on_light = M.suggest_contrast_fix("#7c6fd6", "#ffffff", 7.0)
    assert M.relative_luminance(M.parse_hex(on_dark[:hex])) > M.relative_luminance(M.parse_hex("#7c6fd6"))
    assert M.relative_luminance(M.parse_hex(on_light[:hex])) < M.relative_luminance(M.parse_hex("#7c6fd6"))
  end

  def test_suggest_contrast_fix_returns_nil_when_unreachable
    # Nothing can reach 21:1 against mid grey.
    assert_nil M.suggest_contrast_fix("#808080", "#808080", 21.0)
  end

  # --- geometry autofix selector derivation -------------------------------

  A = Deploy::GeometryAutofix

  def test_css_selector_keeps_the_last_two_steps
    assert_equal "label.field--check-label > input",
                 A.css_selector("div.sidebar-card.newsletter-cta>form>label.field--check-label>input")
  end

  def test_css_selector_anchors_on_the_deepest_id
    assert_equal "#sections > a.section", A.css_selector("div.wrap>#sections>a.section")
  end

  def test_css_selector_strips_occurrence_suffix
    assert_equal "ul.menu > li.item", A.css_selector("nav.main>ul.menu>li.item[3]")
  end

  def test_css_selector_refuses_a_bare_tag
    assert_nil A.css_selector("div"), "patching a bare element selector would hit the whole app"
    assert_nil A.css_selector("")
  end

  def test_render_emits_one_rule_per_selector_not_per_finding
    findings = [
      { app: "brgen", selector: "form>label.check>input", kind: :touch, detail: "mobile" },
      { app: "brgen", selector: "form>label.check>input", kind: :touch, detail: "desktop" },
    ]
    body = A.render(findings)
    assert_equal 1, body.lines.count { |l| l.include?("min-height: 44px") }
  end

  def test_render_uses_the_right_declaration_per_kind
    body = A.render([{ app: "brgen", selector: "div.grid>ul.row", kind: :overflow, detail: nil }])
    assert_includes body, "max-width: 100%"
    refute_includes body, "min-height"
  end

  # --- @use placement ------------------------------------------------------
  #
  # Sass rejects a @use that follows any other rule. Appending to the end of
  # application.scss happens to work when the file is nothing but @use lines
  # and is a compile error when it is not — and a failed compile truncated
  # bsdports' stylesheet from 52KB to 733 bytes. Placement is load-bearing.

  def with_stylesheet(body)
    Dir.mktmpdir do |dir|
      entry = File.join(dir, "application.scss")
      File.write(entry, body)
      A.register_use("brgen", entry)
      yield File.read(entry)
    end
  end

  def test_use_is_inserted_after_the_last_existing_use
    with_stylesheet(%(@use "a";\n@use "b";\n\n.rule { color: red; }\n)) do |out|
      use_line = out.lines.index { |l| l.include?("_autofix_geometry") }
      rule_line = out.lines.index { |l| l.include?(".rule") }
      assert use_line < rule_line, "@use must precede every other rule:\n#{out}"
      assert_equal 2, use_line, "it belongs directly after the last existing @use"
    end
  end

  def test_use_is_not_appended_to_a_file_that_ends_in_rules
    with_stylesheet(%(@use "a";\n.one { color: red; }\n.two { color: blue; }\n)) do |out|
      refute out.lines.last.include?("_autofix_geometry"),
             "appending after real rules is the exact Sass error that truncated bsdports"
    end
  end

  def test_use_goes_after_the_header_comment_when_no_use_exists
    with_stylesheet(%(// header comment\n\n.rule { color: red; }\n)) do |out|
      use_line = out.lines.index { |l| l.include?("_autofix_geometry") }
      rule_line = out.lines.index { |l| l.include?(".rule") }
      assert use_line < rule_line, "@use must still precede the first rule:\n#{out}"
      assert_match(%r{\A// header comment}, out, "the header comment stays first")
    end
  end

  def test_register_use_is_idempotent
    with_stylesheet(%(@use "a";\n@use "_autofix_geometry";\n.rule { color: red; }\n)) do |out|
      assert_equal 1, out.scan("_autofix_geometry").size
    end
  end

  # --- mutation catalogue --------------------------------------------------

  GOOD = <<~HTML
    <html><body>
      <a class="skip-link" href="#main-content">Skip to main content</a>
      <nav aria-label="Primary navigation"><a href="/">Home</a></nav>
      <main id="main-content">
        <h1>Listings</h1>
        <img src="a.png" alt="A thing">
        <button type="submit">Buy</button>
        <p>Body copy long enough to clear the density floor for the quality scorer.</p>
      </main>
    </body></html>
  HTML

  def mutation(id)
    Deploy::GateMutationGate::MUTATIONS.find { |m| m[0] == id }[2]
  end

  def test_each_mutation_actually_changes_the_document
    applied = Deploy::GateMutationGate::MUTATIONS.filter_map do |id, _desc, transform|
      result = transform.call(GOOD.dup)
      id if result && result != GOOD
    end
    assert_operator applied.size, :>=, 7,
                    "most of the catalogue must apply to a representative fixture, applied: #{applied.inspect}"
  end

  def test_drop_h1_removes_the_heading
    refute_match(/<h1/i, mutation(:drop_h1).call(GOOD.dup))
  end

  def test_duplicate_h1_creates_two
    assert_equal 2, mutation(:duplicate_h1).call(GOOD.dup).scan(/<h1\b/i).size
  end

  def test_auth_wall_injects_the_gating_copy
    assert_match(/Sign in to continue/, mutation(:auth_wall).call(GOOD.dup))
  end

  def test_mute_buttons_empties_the_accessible_name
    mutated = mutation(:mute_buttons).call(GOOD.dup)
    assert_match(%r{<button[^>]*></button>}, mutated)
  end

  def test_strip_alt_is_inapplicable_without_images
    assert_nil mutation(:strip_alt).call("<html><body><p>no images</p></body></html>"),
               "a mutation with nothing to break must report inapplicable, not survived"
  end

  def test_gut_content_is_inapplicable_to_an_already_thin_page
    assert_nil mutation(:gut_content).call("<html><body><p>tiny</p></body></html>")
  end

  # --- snapshot diffing ----------------------------------------------------

  def snapshot(overrides = {})
    {
      "title" => "Listings", "viewport" => [390, 844], "scroll_width" => 390, "h1_count" => 1,
      "landmarks" => { "main" => true, "nav" => true, "skip" => true },
      "elements" => [{
        "key" => "nav.tab-bar", "tag" => "nav", "rect" => { "x" => 0, "y" => 0, "w" => 390, "h" => 48 },
        "color" => "#ffffff", "bg" => "#000000", "font_size" => 16.0,
        "line_height" => 24.0, "display" => "flex", "position" => "fixed",
      }],
    }.merge(overrides)
  end

  def compare(a, b)
    Deploy::LayoutSnapshotGate.new.send(:compare, a, b)
  end

  def test_identical_snapshots_do_not_drift
    assert_empty compare(snapshot, snapshot)
  end

  def test_sub_pixel_movement_is_tolerated
    moved = snapshot
    moved["elements"] = [moved["elements"].first.merge("rect" => { "x" => 0, "y" => 1, "w" => 390, "h" => 49 })]
    assert_empty compare(snapshot, moved), "a 1px shift is rounding, not a regression"
  end

  def test_a_real_move_is_reported_with_both_values
    moved = snapshot
    moved["elements"] = [moved["elements"].first.merge("rect" => { "x" => 0, "y" => 0, "w" => 390, "h" => 32 })]
    diffs = compare(snapshot, moved)
    assert_equal 1, diffs.size
    assert_match(/h 48→32/, diffs.first, "the diff must name the old and new value, not just 'changed'")
  end

  def test_colour_change_is_reported
    recoloured = snapshot
    recoloured["elements"] = [recoloured["elements"].first.merge("color" => "#969696")]
    assert_match(/color "#ffffff" → "#969696"/, compare(snapshot, recoloured).first)
  end

  def test_lost_landmark_is_reported
    assert_match(/landmark skip: true → false/,
                 compare(snapshot, snapshot("landmarks" => { "main" => true, "nav" => true, "skip" => false })).first)
  end

  def test_added_and_removed_elements_are_reported
    empty = snapshot("elements" => [])
    assert_match(/removed: nav.tab-bar/, compare(snapshot, empty).join(" "))
    assert_match(/added: nav.tab-bar/, compare(empty, snapshot).join(" "))
  end

  # --- surface configuration ----------------------------------------------

  def test_surfaces_without_a_host_fall_back_to_loopback
    surface = Deploy::GeometryProbe::Surface.new(
      app: "amber", label: "home", host: nil, path: "/items", viewport: "mobile",
      width: 390, height: 844, snapshot: true, port: 61_352
    )
    assert_equal "http://127.0.0.1:61352/items", surface.url
  end

  def test_surfaces_with_a_host_use_the_vanity_domain
    surface = Deploy::GeometryProbe::Surface.new(
      app: "brgen", label: "marketplace", host: "markedsplass.brgen.no", path: "/",
      viewport: "mobile", width: 390, height: 844, snapshot: true, port: 38_182
    )
    assert_equal "http://markedsplass.brgen.no/", surface.url
  end

  def test_host_map_only_includes_surfaces_that_declare_a_host
    map = Deploy::GeometryProbe.host_map
    assert map.keys.any? { |h| h.end_with?("brgen.no") }, "brgen verticals must be resolvable"
    assert map.values.all? { |v| v.start_with?("127.0.0.1:") }
  end

  FakeResult = Struct.new(:fails) do
    def initialize
      super([])
    end

    def fail(msg, severity: :soft)
      fails << msg
    end
  end

  def type_surface(label, width = 1440)
    Deploy::GeometryProbe::Surface.new(
      app: "brgen", label: label, host: nil, path: "/", viewport: "desktop",
      width: width, height: 900, snapshot: false, port: 38_182
    )
  end

  def test_marketplace_wears_the_catalog_profile
    assert_equal "catalog", Deploy::GeometryType.profile_for("marketplace")
    assert Deploy::GeometryType.profile("marketplace")["require_tabular_nums"]
  end

  def test_dating_and_playlist_wear_immersive
    assert_equal "immersive", Deploy::GeometryType.profile_for("dating")
    assert_equal "immersive", Deploy::GeometryType.profile_for("playlist")
    assert_equal 0, Deploy::GeometryType.profile("dating")["measure_min_ch"]
  end

  def test_worn_measure_flags_prose_outside_the_profile
    result = FakeResult.new
    data = { "prose" => [{ "sel" => "p.body", "ch" => 90 }, { "sel" => "p.lede", "ch" => 88 }] }
    Deploy::GeometryType.check_measure(result, type_surface("core"), data, Deploy::GeometryType.profile("feed"))
    assert result.fails.any? { |m| m.include?("bringhurst") }, result.fails.inspect
  end

  def test_catalog_flags_prices_without_tabular_nums
    result = FakeResult.new
    data = { "tabular" => [{ "sel" => ".deal-price", "numeric" => "normal", "text" => "kr 100" }] }
    Deploy::GeometryType.check_tabular(result, type_surface("marketplace"), data, Deploy::GeometryType.profile("marketplace"))
    assert result.fails.any? { |m| m.include?("tabular") }, result.fails.inspect
  end

  def test_type_walk_script_is_present
    path = File.join(__dir__, "../../gates/support/geometry_type_walk.js")
    src = File.read(path)
    assert_includes src, "firstLineChars"
    assert_includes src, "empty_ratio"
    assert_includes src, "fontVariantNumeric"
  end
end
