# frozen_string_literal: true

require_relative "test_helper"
require "zlib"
require File.expand_path("../../MASTER/gates/support/geometry_probe", __dir__)

# The cross-page overlay layers different pages of one app. The browser does
# the compositing, so these drive it with a fake CDP that records the page it
# was shown and writes a PNG header; assertions read the page and the numbers.
class VisualCrossPageOverlayTest < Minitest::Test
  Overlay = Master::Fix::VisualCrossPageOverlay
  Drift = Master::Fix::VisualCrossPageDrift
  Surface = Struct.new(:id, :viewport, :url)

  def self.png(width, height)
    ihdr = [width, height, 8, 2, 0, 0, 0].pack("NNCCCCC")
    "\x89PNG\r\n\x1a\n".b + ([ihdr.bytesize].pack("N") + "IHDR" + ihdr + [Zlib.crc32("IHDR" + ihdr)].pack("N")).b
  end

  class FakeCdp
    attr_reader :navigated

    def initialize = @navigated = []
    def viewport(_width, _height, mobile:) = nil
    def navigate(url) = @navigated << url
    def screenshot(path, capture_beyond_viewport:) = File.binwrite(path, VisualCrossPageOverlayTest.png(10, 10))
  end

  def setup
    @dir = Dir.mktmpdir("cross-page")
  end

  def teardown = FileUtils.rm_rf(@dir)

  def el(tag, key, x: 0, y: 0, w: 100, h: 20, **extra)
    { "tag" => tag, "key" => key, "frect" => { "x" => x, "y" => y, "w" => w, "h" => h } }.merge(extra.transform_keys(&:to_s))
  end

  def capture(id, width: 390, height: 800, header_h: 60, nav_x: 10, state: "resting")
    shot = File.join(@dir, "#{id.tr("/", "_")}.png")
    File.binwrite(shot, self.class.png(width, height))
    elements = [el("header", "body>header", h: header_h), el("nav", "body>header>nav"),
                el("a", "body>header>nav>a", x: nav_x, y: 5), el("main", "body>main", x: 16, y: header_h),
                el("footer", "body>footer", y: 700), el("button", "body>main>button", interactive: true)]
    { surface: Surface.new(id, id.split("/").last, "http://x/"), screenshot: shot,
      payload: { "composition" => { "state" => state }, "elements" => elements } }
  end

  def test_role_is_the_last_word_of_the_label
    assert_equal "index", Overlay.role_of("posts_index")
    assert_equal "show", Overlay.role_of("pages_show_2")
    assert_equal "form", Overlay.role_of("passwords_new")
    assert_equal "form", Overlay.role_of("sign_in")
    assert_equal "page", Overlay.role_of("home")
  end

  def test_pages_of_one_role_are_layered_at_equal_low_opacity
    captures = [capture("amber/posts_index/mobile"), capture("amber/notifications_index/mobile", header_h: 64),
                capture("amber/passwords_new/mobile"), capture("bsdports/categories_index/mobile")]
    cdp = FakeCdp.new
    Overlay.new(dir: @dir).capture(captures, cdp:)
    overlays = Overlay.collect(captures)

    index = overlays.find { |o| o[:key] == "role__amber__mobile__index" }
    assert_equal 2, index[:layers]
    assert_equal 1, overlays.count { |o| o[:kind] == :role }, "a role with one page, or another app, makes no group"
    html = File.read(index[:screenshot].sub(/\.png\z/, ".html"))
    assert_equal ["0.35", "0.35"], html.scan(/<img [^>]*style="opacity:([\d.]+);"/).flatten
    assert_includes html, "top-left aligned"
    assert_includes html, 'stroke="#06b6d4"'
    assert_includes html, ">footer<"
    assert cdp.navigated.all? { |u| u.start_with?("file://#{@dir}/") }
  end

  def test_opacity_is_clamped_and_layers_bounded
    captures = (1..12).map { |i| capture("amber/page#{i}_index/mobile") }
    Overlay.new(dir: @dir).capture(captures, cdp: FakeCdp.new)
    overlay = Overlay.collect(captures).first
    html = File.read(overlay[:screenshot].sub(/\.png\z/, ".html"))

    assert_equal Overlay::MAX_LAYERS, overlay[:layers]
    assert_equal ["0.125"], html.scan(/opacity:([\d.]+);/).flatten.uniq
  end

  def test_drift_numbers_name_the_chrome_that_moved
    captures = [capture("amber/a_index/mobile", header_h: 60, nav_x: 10), capture("amber/b_index/mobile", header_h: 64, nav_x: 10)]
    Overlay.new(dir: @dir).capture(captures, cdp: FakeCdp.new)
    overlay = Overlay.collect(captures).first
    row = overlay[:drift].find { |r| r[:metric] == "header_h" }

    assert_equal 4.0, row[:spread]
    assert_equal({ "amber/a_index/mobile" => 60.0, "amber/b_index/mobile" => 64.0 }, row[:values])
    assert_equal [], Drift.drifted(overlay[:drift]).reject { |r| r[:metric] == "header_h" }.select { |r| r[:metric].start_with?("nav") }
    assert_includes overlay[:text], "header_h spread=4.0px"
  end

  def test_mobile_over_desktop_clips_to_mobile_width_without_scaling
    captures = [capture("amber/posts_index/mobile", width: 390), capture("amber/posts_index/desktop", width: 1280)]
    Overlay.new(dir: @dir).capture(captures, cdp: FakeCdp.new)
    pair = Overlay.collect(captures).find { |o| o[:kind] == :viewport }
    html = File.read(pair[:screenshot].sub(/\.png\z/, ".html"))

    assert_includes html, 'class="stage" style="width:390px;'
    assert_includes pair[:text], "clipped to its left 390px"
    assert_includes html, "not scaled"
  end

  def test_only_resting_captures_are_overlaid
    captures = [capture("amber/a_index/mobile"), capture("amber/b_index/mobile", state: "menu_open")]
    Overlay.new(dir: @dir).capture(captures, cdp: FakeCdp.new)

    assert_empty Overlay.collect(captures)
  end

  def test_contact_sheet_and_rows_carry_the_overlays
    captures = [capture("amber/a_index/mobile"), capture("amber/b_index/mobile", header_h: 70)]
    Overlay.new(dir: @dir).capture(captures, cdp: FakeCdp.new)
    html = Master::Fix::VisualContactSheet.new(dir: @dir, root: @dir).send(:page, captures)

    assert_equal 1, html.scan("<figcaption>cross-page overlay | amber mobile index pages | 2 pages</figcaption>").size, "shared by two captures, shown once"

    host = Object.new.extend(Master::Fix::VisualEvidenceRows)
    assert_includes host.send(:cross_page_context, captures), "header_h spread=10.0px"
    assert_includes host.send(:cross_page_context, captures), "double edge"
    assert_includes host.send(:cross_page_context, []), "none"
  end

  def test_fullres_images_are_bounded_by_env_and_lead_with_overlays
    captures = [capture("amber/a_index/mobile"), capture("amber/b_index/mobile"), capture("amber/c_new/mobile")]
    Overlay.new(dir: @dir).capture(captures, cdp: FakeCdp.new)
    host = Object.new.extend(Master::Fix::VisualEvidenceRows)
    previous = ENV["MASTER_VISUAL_FULLRES_IMAGES"]
    ENV["MASTER_VISUAL_FULLRES_IMAGES"] = "2"
    images = host.send(:fullres_images, captures)

    assert_equal 2, images.size
    assert_includes images.first[:name], "cross-page-"
    ENV["MASTER_VISUAL_FULLRES_IMAGES"] = "0"
    assert_empty host.send(:fullres_images, captures)
  ensure
    ENV["MASTER_VISUAL_FULLRES_IMAGES"] = previous
  end

  def test_critique_extends_the_single_image_without_breaking_it
    critique = Master::Review::Council::Critique.allocate
    primary = { path: "a.png", name: "a", mime: "image/png" }
    extra = { path: "b.png", name: "b", mime: "image/png" }

    assert_equal primary, critique.send(:with_extra_images, primary, nil)
    assert_equal [extra], critique.send(:with_extra_images, primary, [extra])[:extra]
    assert_nil critique.send(:with_extra_images, nil, nil)
  end
end
