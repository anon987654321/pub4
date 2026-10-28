# frozen_string_literal: true

require_relative "test_helper"
require File.expand_path("../lib/fix/visual_quality_checks", __dir__)
require File.expand_path("../checks/support/painted_fonts", __dir__)
require File.expand_path("../checks/support/focus_order_probe", __dir__)
require File.expand_path("../checks/support/locale_probe", __dir__)

# Painted fonts, both locales and the recorded Tab order, each on synthetic
# payloads or a scripted CDP double: no browser is needed to prove the
# decisions, only to prove the protocol, which the live run reports.
class TestVisualProbes < Minitest::Test
  Surface = Struct.new(:id, :viewport, :url)
  VC = Master::Fix::VisualConformance
  Q = Master::Fix::VisualQualityChecks
  I18N = Master::Fix::VisualI18n
  FO = Master::Fix::VisualFocusOrder

  def surface(app = "brgen") = Surface.new("#{app}/home/mobile", "mobile", "http://127.0.0.1:1/")

  # --- painted fonts ---------------------------------------------------------

  def el(key, family, **over)
    { "key" => key, "font_family" => family, "text" => "hei", "visible" => true }.merge(over)
  end

  def fonts(payload, *elements) = VC.check_payload(surface, { "elements" => elements }.merge(payload))

  def test_a_declined_web_font_is_caught_by_what_was_painted
    stack = '"Helvetica Neue Pro", Arial, sans-serif'
    assert_empty fonts({}, el("p.a", stack))
    painted = { "painted_fonts" => { "p.a" => [{ "name" => "Times New Roman", "glyphs" => 40 }] }, "painted_fonts_status" => "ok" }
    found = fonts(painted, el("p.a", stack))
    assert_equal ["p.a"], found.map(&:selector).uniq
    assert(found.any? { |f| f.detail.include?("times new roman") })
  end

  def test_painted_house_face_and_generic_head_pass
    ok = { "painted_fonts" => { "p.a" => [{ "name" => "Helvetica Neue", "glyphs" => 40 }], "p.b" => [{ "name" => "DejaVu Sans", "glyphs" => 9 }] } }
    assert_empty fonts(ok, el("p.a", "Helvetica Neue Pro, Arial"), el("p.b", "sans-serif"))
  end

  def test_unverified_probe_falls_back_to_computed_and_says_so
    payload = { "painted_fonts_status" => "unverified: CDP returned no platform fonts" }
    found = fonts(payload, el("p.a", "Georgia, serif"))
    assert_match(/\[unverified: CDP returned no platform fonts; computed stack only\]/, found.first.detail)
  end

  class FakeCdp
    attr_reader :calls

    def initialize(keys:, fonts:, fail_on: nil)
      @keys = keys
      @fonts = fonts
      @fail_on = fail_on
      @calls = []
    end

    def evaluate(js, **)
      @calls << :evaluate
      js.include?("data-gp-font', String") ? @keys : nil
    end

    def command(method, **params)
      @calls << method
      raise Deploy::CdpSession::Error, "no #{method}" if method == @fail_on

      case method
      when "DOM.getDocument" then { "root" => { "nodeId" => 1 } }
      when "DOM.querySelectorAll" then { "nodeIds" => @fonts.keys }
      when "DOM.getAttributes" then { "attributes" => ["data-gp-font", @fonts.fetch(params[:nodeId])[:index].to_s] }
      when "CSS.getPlatformFontsForNode" then { "fonts" => @fonts.fetch(params[:nodeId])[:rows] }
      else {}
      end
    end
  end

  def test_probe_ranks_platform_fonts_by_glyphs
    rows = [{ "familyName" => "Arial", "glyphCount" => 3 }, { "familyName" => "Helvetica Neue", "glyphCount" => 30 }]
    cdp = FakeCdp.new(keys: %w[h1.t], fonts: { 7 => { index: 0, rows: } })
    out = Deploy::PaintedFonts.probe(cdp)
    assert_equal "ok", out["painted_fonts_status"]
    assert_equal ["Helvetica Neue", "Arial"], out["painted_fonts"]["h1.t"].map { |f| f["name"] }
  end

  def test_probe_flags_unverified_when_cdp_lacks_the_method
    cdp = FakeCdp.new(keys: %w[h1.t], fonts: {}, fail_on: "CSS.getPlatformFontsForNode")
    cdp.define_singleton_method(:command) { |m, **| raise Deploy::CdpSession::Error, "'#{m}' wasn't found" if m == "CSS.enable"; { "root" => { "nodeId" => 1 }, "nodeIds" => [] } }
    out = Deploy::PaintedFonts.probe(cdp)
    assert_match(/\Aunverified/, out["painted_fonts_status"])
    refute out.key?("painted_fonts")
  end

  def test_probe_samples_at_most_the_bound
    seen = nil
    cdp = FakeCdp.new(keys: [], fonts: {})
    cdp.define_singleton_method(:evaluate) { |js, **| seen ||= js[/const LIMIT = (\d+)/, 1]; [] }
    Deploy::PaintedFonts.probe(cdp)
    assert_equal "60", seen
  end

  # --- locales ---------------------------------------------------------------

  def texts(**pairs) = pairs.to_h { |k, (t, tag)| [k.to_s, [t, tag]] }

  def locales(nb, en) = { "locales" => { "nb" => { "lang" => "nb", "texts" => nb }, "en" => { "lang" => "en", "texts" => en } } }

  def test_keys_as_text_and_missing_marker_are_found_in_the_second_locale
    payload = locales(texts(a: %w[Hjem a]), texts(a: ["home.index.title", "a"], b: ["translation missing: en.x", "p"]))
    assert_equal ["a [en]", "b [en]"], I18N.rows(payload).map { |r| r["key"] }
  end

  def test_identical_ui_label_is_flagged_but_names_and_content_are_not
    nb = texts("header.top>a": ["Log in to continue", "a"], "main>h1": ["Welcome back friends", "h1"], "form>button": ["Save changes", "button"],
               "footer>p": ["Ragnhild Hansen", "p"], "nav>a": ["www.brgen.no", "a"], "form>label": %w[Chat label])
    found = I18N.rows(locales(nb, nb)).map { |r| r["key"] }
    assert_equal 2, found.size
    assert(found.all? { |k| k.include?("nb=en") })
    assert(found.any? { |k| k.start_with?("form>button") })
    assert(found.any? { |k| k.start_with?("header.top>a") })
  end

  def test_translated_labels_pass_and_unavailable_locale_is_skipped
    ok = locales(texts("form>button": ["Lagre endringer", "button"]), texts("form>button": ["Save changes", "button"]))
    assert_empty I18N.rows(ok)
    pinned = { "locales" => { "nb" => { "texts" => texts(a: %w[Hjem a]) }, "en" => { "status" => "unavailable", "lang" => "nb" } } }
    assert_empty I18N.rows(pinned)
  end

  def test_the_check_counts_second_locale_defects_in_the_i18n_metric
    payload = { "vw" => 390, "vh" => 800, "scroll_width" => 390, "client_width" => 390, "elements" => [] }
    bad = locales(texts(a: %w[Hjem a]), texts(a: ["home.index.title", "a"]))
    assert_equal 1, Q.measure(surface, payload.merge(bad))["metrics"]["i18n"]
  end

  class LocaleCdp
    attr_reader :urls, :headers_seen

    def initialize(html_lang:, pinned: nil)
      @lang = html_lang
      @pinned = pinned
      @urls = []
      @headers_seen = []
    end

    def evaluate(js, **)
      return @lang_now || @lang if js.include?("getAttribute('lang')")

      { "elements" => [{ "key" => "button.go", "tag" => "button", "text" => "Save", "visible" => true }] }
    end

    def headers(h) = @headers_seen << h["Accept-Language"]
    def clear_cookies = nil

    def navigate(url)
      @urls << url
      @lang_now = @pinned || url[/locale=(\w+)/, 1] || @lang
    end
  end

  def test_locale_probe_visits_the_other_locale_then_restores_the_page
    cdp = LocaleCdp.new(html_lang: "nb-NO")
    payload = Deploy::LocaleProbe.attach(cdp, surface, { "elements" => [{ "key" => "a", "tag" => "a", "text" => "Hjem", "visible" => true }] })
    assert_equal %w[nb en], payload["locales"].keys
    assert_equal "Save", payload["locales"]["en"]["texts"]["button.go"][0]
    assert_equal ["http://127.0.0.1:1/?locale=en", "http://127.0.0.1:1/"], cdp.urls
    assert_equal "en", cdp.headers_seen.first
  end

  def test_locale_probe_reports_a_surface_pinned_to_one_language
    cdp = LocaleCdp.new(html_lang: "nb", pinned: "nb")
    payload = Deploy::LocaleProbe.attach(cdp, surface, { "elements" => [] })
    assert_equal "unavailable", payload["locales"]["en"]["status"]
  end

  def test_env_narrows_the_locales
    previous = ENV["MASTER_VISUAL_LOCALES"]
    ENV["MASTER_VISUAL_LOCALES"] = "nb"
    cdp = LocaleCdp.new(html_lang: "nb")
    assert_equal({ "elements" => [] }, Deploy::LocaleProbe.attach(cdp, surface, { "elements" => [] }))
    assert_empty cdp.urls
  ensure
    ENV["MASTER_VISUAL_LOCALES"] = previous
  end

  # --- focus order -----------------------------------------------------------

  def stop(key, x, y, w: 80, h: 30, **over) = { "key" => key, "x" => x, "y" => y, "w" => w, "h" => h }.merge(over)

  def order(stops, **over) = { "tab_order" => stops, "elements" => [] }.merge(over)

  def test_recorded_tab_order_reports_a_backward_jump_with_selectors
    payload = order([stop("a.logo", 0, 10), stop("a.cta", 0, 600), stop("a.menu", 300, 10)])
    assert_equal ["a.menu"], FO.inversions([], payload).map { |s| s["key"] }
  end

  def test_row_then_wrap_is_reading_order_and_dom_order_alone_is_not_consulted
    payload = order([stop("a.1", 0, 10), stop("a.2", 100, 10), stop("a.3", 200, 10), stop("a.4", 0, 60)])
    assert_empty FO.inversions([], payload)
    dom = [{ "key" => "late", "interactive" => true, "rect" => { "x" => 0, "y" => 500, "w" => 50, "h" => 30 } },
           { "key" => "early", "interactive" => true, "rect" => { "x" => 0, "y" => 5, "w" => 50, "h" => 30 } }]
    assert_empty FO.inversions(dom, payload), "the recorded sequence outranks document order"
    assert_equal ["early"], FO.inversions(dom, {}).map { |s| s["key"] }
  end

  def test_same_row_going_left_is_an_inversion_in_ltr_and_not_in_rtl
    stops = [stop("a.right", 300, 10), stop("a.left", 20, 10)]
    assert_equal ["a.left"], FO.inversions([], order(stops)).map { |s| s["key"] }
    assert_empty FO.inversions([], order(stops, "text_dir" => "rtl"))
    assert_equal ["a.right"], FO.inversions([], order(stops.reverse, "text_dir" => "rtl")).map { |s| s["key"] }
  end

  def test_fixed_stops_are_skipped
    payload = order([stop("a.1", 0, 400), stop("button.chat", 0, 10, "position" => "fixed"), stop("a.2", 0, 450)])
    assert_empty FO.inversions([], payload)
  end

  def test_the_check_metric_uses_the_recorded_order
    payload = order([stop("a", 0, 500), stop("b", 0, 10)], "vw" => 390, "vh" => 800, "scroll_width" => 390, "client_width" => 390)
    assert_equal 1, Q.measure(surface, payload)["metrics"]["focus_order"]
  end

  class TabCdp
    def initialize(stops) = (@stops = stops; @i = -1)
    def press(_key) = @i += 1

    def evaluate(js, **)
      return "ltr" if js.include?("direction")

      @stops[@i]
    end
  end

  def test_tab_probe_records_stops_until_focus_wraps
    a = { "sel" => "a.one", "x" => 0, "y" => 0 }
    b = { "sel" => "a.two", "x" => 50, "y" => 0 }
    out = Deploy::FocusOrderProbe.probe(TabCdp.new([a, b, a.dup, nil]))
    assert_equal %w[a.one a.two], out["tab_order"].map { |s| s["sel"] }
    assert_equal "ok", out["tab_order_status"]
  end

  def test_tab_probe_is_bounded
    cdp = TabCdp.new(Array.new(500) { |i| { "sel" => "a.n#{i}", "x" => i, "y" => 0 } })
    assert_equal 60, Deploy::FocusOrderProbe.probe(cdp)["tab_order"].size
  end

  def test_malformed_active_element_response_is_unverified
    cdp = Object.new
    cdp.define_singleton_method(:press) { |_key| nil }
    cdp.define_singleton_method(:evaluate) do |js, **|
      js.include?("direction") ? "ltr" : "not-an-element"
    end

    result = Deploy::FocusOrderProbe.probe(cdp)

    assert_match(/unverified/, result["tab_order_status"])
    refute result.key?("tab_order")
  end
end
