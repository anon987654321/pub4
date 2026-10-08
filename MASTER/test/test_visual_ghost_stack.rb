# frozen_string_literal: true

require_relative "test_helper"
require "zlib"
require File.expand_path("../../MASTER/gates/support/geometry_probe", __dir__)

# VisualGhostStack keeps a bounded history per surface and state, and renders
# evidence pages from it through whatever browser session /fix already holds.
# These drive it with a fake CDP session that writes a real PNG header, so every
# assertion is about what capture stored, returned or asked the browser to show.
class VisualGhostStackContractTest < Minitest::Test
  Stack = Master::Fix::VisualGhostStack
  Pages = Master::Fix::VisualGhostPages
  Surface = Struct.new(:id, :viewport, :url)

  def self.png(width, height)
    ihdr = [width, height, 8, 2, 0, 0, 0].pack("NNCCCCC")
    chunk = [ihdr.bytesize].pack("N") + "IHDR" + ihdr + [Zlib.crc32("IHDR" + ihdr)].pack("N")
    "\x89PNG\r\n\x1a\n".b + chunk.b
  end

  # Records what the stack asked of the browser; a screenshot is a PNG header.
  class FakeCdp
    attr_reader :navigated, :viewports

    def initialize
      @navigated = []
      @viewports = []
    end

    def viewport(width, height, mobile:) = @viewports << [width, height, mobile]
    def navigate(url) = @navigated << url
    def screenshot(path, capture_beyond_viewport:) = File.binwrite(path, VisualGhostStackContractTest.png(1800, 1400))
  end

  def setup
    @root = Dir.mktmpdir("ghost-root")
    @dir = Dir.mktmpdir("ghost-dir")
    @surface = Surface.new("master/chat/mobile", "mobile", "http://127.0.0.1/")
    @previous_run = ENV["MASTER_VISUAL_RUN_ID"]
  end

  def teardown
    ENV["MASTER_VISUAL_RUN_ID"] = @previous_run
    FileUtils.rm_rf(@root)
    FileUtils.rm_rf(@dir)
  end

  def stack(run_id)
    ENV["MASTER_VISUAL_RUN_ID"] = run_id
    Stack.new(root: @root, dir: @dir)
  end

  def capture_with(ghosts, pass, elements: [], cdp: FakeCdp.new, state: "resting")
    shot = File.join(@dir, "shot-#{pass}.png")
    File.binwrite(shot, self.class.png(390, 844))
    payload = { "composition" => { "state" => state }, "elements" => elements }
    ghosts.capture({ surface: @surface, screenshot: shot, payload: }, pass:, cdp:)
  end

  def history_dir = File.join(@root, "MASTER", ".master", "visual_evidence", "master_chat_mobile__resting")

  def page_for(png)
    File.read(png.sub(/\.png\z/, ".html"))
  end

  def element(key, x:, y: 10, w: 100, h: 20, font_size: 16, line_height: 24)
    { "key" => key, "text" => key, "frect" => { "x" => x, "y" => y, "w" => w, "h" => h },
      "font_size" => font_size, "line_height" => line_height }
  end

  def test_history_is_persistent_but_bounded
    first = stack("run-a")
    3.times { |i| capture_with(first, i + 1) }
    second = stack("run-b")
    result = nil
    4.times { |i| result = capture_with(second, i + 1) }

    assert_equal Stack::HISTORY_LIMIT, Dir.glob(File.join(history_dir, "*.png")).size
    assert_equal Stack::HISTORY_LIMIT, Dir.glob(File.join(history_dir, "*.json")).size
    assert_equal Stack::HISTORY_LIMIT, result[:history].size
    assert result[:history].all? { |path| path.start_with?(history_dir) }, "history lives under MASTER/.master/visual_evidence"
    assert_equal "run-b-pass-000004.png", File.basename(result[:history].last)
  end

  def test_run_id_defaults_to_a_microsecond_utc_stamp
    ENV.delete("MASTER_VISUAL_RUN_ID")
    result = capture_with(Stack.new(root: @root, dir: @dir), 1)

    assert_match(/\A\d{8}T\d{12}-pass-000001\.png\z/, File.basename(result[:history].last))
  end

  def test_pass_number_cannot_overwrite_a_previous_fix_run
    capture_with(stack("run-a"), 1)
    result = capture_with(stack("run-b"), 1)

    assert_equal %w[run-a-pass-000001.png run-b-pass-000001.png], result[:history].map { |p| File.basename(p) }
  end

  def test_visual_stack_is_aligned_and_uses_low_opacity_history
    ghosts = stack("run")
    result = nil
    5.times { |i| result = capture_with(ghosts, i + 1) }
    html = page_for(result[:ghost][:screenshot])

    assert_includes html, "position:absolute;inset:0"
    opacities = html.scan(/class="(\w+)"[^>]*style="opacity:([\d.]+);"/)
    assert_equal Stack::GHOST_OPACITIES.map { |o| ["ghost", o.to_s] } + [["current", Stack::CURRENT_OPACITY.to_s]], opacities
    assert Stack::GHOST_OPACITIES.all? { |o| o < Stack::CURRENT_OPACITY }, "history sits under the current frame"
    assert_includes page_for(result[:ghost][:diff]), "mix-blend-mode:difference"
  end

  def test_geometry_drift_is_part_of_visual_evidence
    ghosts = stack("run")
    before = [element("moved", x: 0), element("retyped", x: 200), element("still", x: 400),
              element("gone", x: 600)]
    before.first["rect"] = { "x" => 999, "y" => 999, "w" => 1, "h" => 1 }
    after = [element("moved", x: 10), element("retyped", x: 200, font_size: 18, line_height: 28),
             element("still", x: 400.4), element("new", x: 800)]
    capture_with(ghosts, 1, elements: before)
    result = capture_with(ghosts, 2, elements: after)
    rows = result[:drift]

    moved = rows.find { |row| row["key"] == "moved" }
    assert_equal({ "x" => 10.0 }, moved["delta"], "frect wins over rect, and only axes past the tolerance count")
    retyped = rows.find { |row| row["key"] == "retyped" }
    assert_equal({ "font_size" => 2.0, "line_height" => 4.0 }, retyped["type"])
    assert_nil rows.find { |row| row["key"] == "still" }, "a move within #{Stack::DIFF_TOLERANCE_PX}px is not drift"
    assert_equal({ "missing" => 1, "added" => 1 }, rows.last["structural"])
  end

  def test_one_frame_renders_stack_grid_and_squint_but_no_pairwise_evidence
    ghost = capture_with(stack("run"), 1)[:ghost]

    %i[screenshot grid squint].each { |kind| assert File.file?(ghost[kind]), "#{kind} rendered" }
    %i[diff geometry focus].each { |kind| assert_nil ghost[kind], "#{kind} needs two frames" }
  end

  def test_visual_evidence_has_registration_and_grid_diagnostics
    ghosts = stack("run")
    cdp = FakeCdp.new
    before = (1..30).map { |i| element("e#{i}", x: i * 20) }
    after = (1..30).map { |i| element("e#{i}", x: i * 20 + i) }
    capture_with(ghosts, 1, elements: before, cdp:)
    result = capture_with(ghosts, 2, elements: after, cdp:)
    ghost = result[:ghost]

    %i[screenshot diff geometry grid focus squint].each { |kind| assert File.file?(ghost[kind]), "#{kind} rendered" }
    assert_equal "master/chat/mobile | resting | 2 aligned passes", ghost[:label]
    assert cdp.navigated.all? { |url| url.start_with?("file://#{@dir}/") }, "evidence pages are local files"
    assert_includes cdp.viewports, [1800, 1400, false]

    geometry = page_for(ghost[:geometry])
    assert_includes geometry, "previous box"
    assert_includes geometry, "current box"
    assert_includes geometry, %(viewBox="0 0 390 844"), "the overlay takes the current frame's own PNG dimensions"
    assert_equal Stack::MAX_GEOMETRY_MARKERS, geometry.scan(/stroke="#06b6d4"/).size

    grid = page_for(ghost[:grid])
    assert_includes grid, "registration grid"
    assert_includes grid, "background-size:#{Stack::REGISTRATION_GRID_PX}px #{Stack::REGISTRATION_GRID_PX}px"
    assert_includes page_for(ghost[:squint]), "blur(#{Stack::SQUINT_BLUR_PX}px)"

    focus = page_for(ghost[:focus])
    assert_includes focus, "focus registration"
    assert_includes focus, "e30 · Δ 30.0px", "focus crops the element that moved most"
    assert_includes focus, "at #{Stack::FOCUS_SCALE}×"
  end

  def test_pages_escape_what_they_are_given
    shot = File.join(@dir, "x.png")
    File.binwrite(shot, self.class.png(4, 4))
    html = Pages.squint(surface: Surface.new("<a>", "mobile", ""), state: "\"s\"", image_path: shot, blur_px: 3)

    assert_includes html, "&lt;a&gt;"
    assert_includes html, "&quot;s&quot;"
  end

  def test_visual_pass_hands_every_capture_to_the_ghost_stack
    pass = Master::Fix::VisualPass.new(agent: Object.new, root: @root)
    pass.instance_variable_set(:@dir, @dir)
    pass.instance_variable_set(:@ghost_stack, stack("run"))
    surface = Deploy::GeometryProbe::Surface.new(app: "master", label: "chat", path: "/", viewport: "mobile", port: 1)
    cdp = FakeCdp.new
    probe = Deploy::GeometryProbe
    captures = probe.stub(:with_browser, ->(**, &blk) { blk.call(cdp) }) do
      probe.stub(:walk, { "elements" => [] }) do
        probe.stub(:ok?, true) do
          Deploy::CompositionProbe.stub(:capture, []) do
            Deploy::MobileJourneyProbe.stub(:run, []) do
              Deploy::WebPlatformProbe.stub(:run, {}) { pass.send(:capture_surfaces, [surface], pass: 1) }
            end
          end
        end
      end
    end

    assert_equal 1, captures.size
    assert File.file?(captures.first.dig(:visual_evidence, :ghost, :screenshot))
  end

  def test_contact_sheet_consumes_the_evidence
    shot = File.join(@dir, "x.png")
    File.binwrite(shot, self.class.png(4, 4))
    ghost = { screenshot: shot, diff: shot, geometry: shot, grid: shot, focus: shot, squint: shot, label: "L" }
    capture = { surface: @surface, screenshot: shot, visual_evidence: { ghost: } }
    html = Master::Fix::VisualContactSheet.new(dir: @dir, root: @root).send(:page, [capture])

    ["L | onion stack", "L | newest vs previous difference", "L | geometry registration",
     "L | registration grid", "L | 2x focus registration", "L | squint composition"].each do |label|
      assert_includes html, "<figcaption>#{label}</figcaption>"
    end
  end
end
