# frozen_string_literal: true

require_relative "test_helper"

# Cross-app consistency reads computed styles the geometry walk captured. These
# tests feed it synthetic captures: no browser ran, so they prove the comparison
# and the amber carve-out, not what the live apps render.
class CrossAppConsistencyTest < Minitest::Test
  Check = Master::Fix::CrossAppConsistency
  Surface = Struct.new(:app, :label, :host, :viewport)

  def button(radius:, size: 16, weight: "500", h: 44, bg: "#0b3d91")
    { "tag" => "button", "interactive" => true, "key" => "main>button", "font_size" => size, "font_weight" => weight,
      "border_radius" => radius, "bg" => bg, "color" => "#fff", "frect" => { "x" => 0, "y" => 0, "w" => 90, "h" => h } }
  end

  def capture(app, els, label: "home", host: nil, viewport: "desktop")
    { surface: Surface.new(app, label, host, viewport), payload: { "elements" => els, "composition" => { "state" => "resting" } } }
  end

  def report(captures) = Check.new(Check.from_captures(captures)).report

  def test_reports_a_primitive_that_differs_between_shared_apps_and_points_at_the_shared_sheet
    r = report([capture("brgen", [button(radius: "4px")]), capture("bsdports", [button(radius: "8px")])])
    row = r[:inconsistencies].find { |x| x[:prop] == "border_radius" }
    assert_equal({ "brgen" => "4px", "bsdports" => "8px" }, row[:values])
    finding = r[:findings].find { |f| f[:prop] == "border_radius" }
    assert_equal "CROSS_APP_CONSISTENCY", finding[:law]
    assert_match %r{RAILS/__shared/app/assets/stylesheets/_buttons\.scss}, finding[:fix_in]
    assert_match(/unify this primitive/, finding[:message])
    assert finding[:advisory]
  end

  def test_agreeing_apps_produce_no_findings
    r = report([capture("brgen", [button(radius: "4px")]), capture("bsdports", [button(radius: "4px")])])
    assert_empty r[:findings]
  end

  def test_numeric_values_within_half_a_pixel_agree
    r = report([capture("brgen", [button(radius: "4px", size: 16.0)]), capture("bsdports", [button(radius: "4px", size: 16.4)])])
    assert_empty r[:findings]
  end

  def test_amber_is_informational_and_never_a_finding
    r = report([capture("brgen", [button(radius: "4px")]), capture("bsdports", [button(radius: "4px")]),
                capture("amber", [button(radius: "0px", weight: "300")])])
    assert_empty r[:findings], "amber's look is not proposed for change"
    props = r[:amber_deviations].map { |d| d[:prop] }
    assert_includes props, "border_radius"
    assert_includes props, "font_weight"
    assert(r[:amber_deviations].all? { |d| d[:informational] })
    assert_match(/not for change/, r[:text])
  end

  def test_viewports_are_compared_only_with_themselves
    r = report([capture("brgen", [button(radius: "4px")], viewport: "mobile"),
                capture("bsdports", [button(radius: "8px")], viewport: "desktop")])
    assert_empty r[:findings]
  end

  def test_a_brgen_vertical_is_its_own_member
    r = report([capture("brgen", [button(radius: "4px")], label: "core"),
                capture("brgen", [button(radius: "12px")], label: "dating", host: "dating.brgen.no")])
    assert_equal %w[brgen brgen:dating], r[:findings].first[:values].keys
  end

  def test_master_face_is_excluded_and_non_resting_states_are_skipped
    shot = capture("brgen", [button(radius: "4px")])
    state = capture("bsdports", [button(radius: "8px")])
    state[:payload]["composition"] = { "state" => "menu_open" }
    r = report([shot, state, capture("master", [button(radius: "99px")])])
    assert_empty r[:findings]
  end

  def test_probe_samples_add_padding_and_border
    a = Check::Sample.new(app: "brgen", viewport: "desktop", primitive: "button", selector: "button.btn", style: { "padding" => "8px 16px 8px 16px" })
    b = Check::Sample.new(app: "bsdports", viewport: "desktop", primitive: "button", selector: "button.btn", style: { "padding" => "4px 8px 4px 8px" })
    r = Check.new([a, b]).report
    assert_equal ["padding"], r[:findings].map { |f| f[:prop] }
  end

  def test_probe_reads_rows_from_the_page
    cdp = Object.new
    def cdp.evaluate(_js) = [{ "primitive" => "footer", "selector" => "footer.site", "style" => { "height" => 80, "padding" => "8px", "x" => nil } }]
    samples = Master::Fix::CrossAppProbe.samples(cdp, Surface.new("bsdports", "home", nil, "mobile"))
    assert_equal "bsdports", samples.first.app
    refute samples.first.style.key?("x")
  end

  def test_report_writes_text_and_json
    Dir.mktmpdir do |dir|
      c = Check.new(Check.from_captures([capture("brgen", [button(radius: "4px")]), capture("bsdports", [button(radius: "8px")])]), out_dir: dir)
      c.write
      assert File.file?(File.join(dir, "cross_app.txt"))
      assert JSON.parse(File.read(File.join(dir, "cross_app.json"))).key?("findings")
    end
  end
end
