# frozen_string_literal: true

require_relative "test_helper"
require "json"

# The face sized to the terminal, and the finer ink ramp it is drawn with.
class TestCliFaceSizing < Minitest::Test
  Face = Master::CLI::Face
  Sizing = Face::Sizing
  FIXTURES = JSON.parse(File.read(File.join(__dir__, "fixtures", "face_ascii_frames.json")))
  PRINTABLE = /\A[\x20-\x7e\n]*\z/

  def teardown
    Sizing.mode = nil
  end

  Console = Struct.new(:winsize)

  def test_winsize_reads_the_console_first
    assert_equal [50, 200], Sizing.winsize(console: Console.new([50, 200]), env: { "LINES" => "9", "COLUMNS" => "9" })
  end

  def test_winsize_falls_back_to_lines_and_columns_then_to_24_by_80
    assert_equal [40, 132], Sizing.winsize(console: nil, env: { "LINES" => "40", "COLUMNS" => "132" })
    assert_equal [40, 132], Sizing.winsize(console: Console.new([0, 0]), env: { "LINES" => "40", "COLUMNS" => "132" })
    assert_equal [24, 80], Sizing.winsize(console: nil, env: {})
    raising = Object.new.tap { |o| def o.winsize = raise(Errno::ENOTTY) }
    assert_equal [24, 80], Sizing.winsize(console: raising, env: { "LINES" => "x" })
  end

  def test_auto_takes_the_room_less_the_margin_up_to_the_cap
    rows, cols = Sizing.fit(200, 500, mode: "auto")
    assert_equal Sizing::CAP[0], rows
    assert_operator cols, :<=, Sizing::CAP[1]
    rows, cols = Sizing.fit(40, 100, mode: "auto")
    assert_equal 40, rows
    assert_operator cols, :<=, 100 - (2 * Sizing::MARGIN.fetch("cols"))
    assert_operator cols, :>=, 60, "a big terminal is nearly all used"
  end

  def test_auto_cuts_a_window_wider_than_the_head_can_use
    rows, cols = Sizing.fit(30, 300, mode: "auto", aspect: 2.0)
    assert_equal 30, rows
    assert_equal (30 * 2.0 * Sizing::SPAN).ceil, cols
    _, wider = Sizing.fit(30, 300, mode: "auto", aspect: 2.4)
    assert_operator wider, :>, cols, "a taller cell leaves room for a wider window"
  end

  def test_the_floor_holds_where_the_terminal_has_room_and_gives_way_where_it_has_not
    rows, cols = Sizing.fit(30, 90, mode: "small")
    assert_equal Sizing::FLOOR, [rows, cols]
    rows, cols = Sizing.fit(12, 40, mode: "small")
    assert_operator rows, :<=, 12
    assert_operator cols, :<=, 40
  end

  def test_large_and_explicit_sizes_are_clamped
    assert_equal Sizing::CAP, Sizing.fit(500, 900, mode: "large")
    assert_equal [40, 100], Sizing.fit(60, 200, mode: "100x40")
    assert_equal Sizing::CAP, Sizing.fit(500, 900, mode: "9000x9000")
    rows, cols = Sizing.fit(20, 60, mode: "300x90")
    assert_operator rows, :<=, 20
    assert_operator cols, :<=, 60
  end

  def test_a_size_word_is_parsed_or_refused
    assert_equal "auto", Sizing.parse(" AUTO ")
    assert_equal "large", Sizing.parse("large")
    assert_equal "160x60", Sizing.parse("160 x 60")
    assert_nil Sizing.parse("huge")
    assert_nil Sizing.parse("")
    Sizing.mode = "small"
    assert_equal "small", Sizing.mode
    Sizing.mode = "bogus"
    assert_equal Sizing::CONFIG.fetch("mode"), Sizing.mode unless ENV["MASTER_FACE_SIZE"]
  end

  def test_the_face_command_takes_a_size
    registry = Master::CLI::CommandRegistry
    assert_nil registry.send(:face_size, "")
    assert_nil registry.send(:face_size, "size large")
    assert_equal "large", Sizing.mode
    assert_nil registry.send(:face_size, "size 120x40")
    assert_equal "120x40", Sizing.mode
    assert_match(/\Aface0: size is auto, small, large or WxH/, registry.send(:face_size, "size enormous"))
    assert_equal "120x40", Sizing.mode, "a refused size changes nothing"
  end

  def test_the_window_gives_the_renderer_the_size_it_chose
    seen = nil
    renderer = ->(**kwargs) do
      seen = [kwargs.fetch(:rows), kwargs.fetch(:cols)]
      Array.new(seen.first, " " * seen.last).join("\n")
    end
    window = Face::Window.new(turn: ->(_) { "" }, ear: Face::Ear.new, mouth: Face::Mouth.new, input: StringIO.new, output: StringIO.new, size_mode: "small")
    Face.stub(:frame, renderer) { window.screen(60, 200, 1.0) }
    assert_equal Sizing::FLOOR, seen
    window = Face::Window.new(turn: ->(_) { "" }, ear: Face::Ear.new, mouth: Face::Mouth.new, input: StringIO.new, output: StringIO.new, size_mode: "large")
    Face.stub(:frame, renderer) { window.screen(60, 200, 1.0) }
    assert_equal 53, seen.first, "the rows the strip below leaves"
    assert_operator seen.last, :>, 100
  end

  def test_the_ramp_has_many_levels_ordered_by_ink_and_clear_of_the_contours
    ascii = Master::Face::Contract.ascii
    glyphs = ascii.fetch("chars").chars
    ink = ascii.fetch("ink")
    assert_operator glyphs.size, :>=, 24
    assert_operator glyphs.size, :<=, 32
    assert_equal glyphs.uniq, glyphs
    glyphs.each_cons(2) { |a, b| assert_operator ink.fetch(b), :>, ink.fetch(a) }
    assert glyphs.all? { |g| g.ord.between?(0x20, 0x7e) }, "printable ASCII only"
    assert_empty glyphs & %w[| - / \\ ' _ ( ) o O], "the contours and features keep their glyphs"
    ascii.fetch("ramps").each_value { |ramp| assert_empty ramp.chars - glyphs, "a named ramp is a subset" }
  end

  def test_levels_rise_from_zero_to_one_in_both_modes
    glyphs = Face::Glyphs::DEFAULT_CHARS.chars
    dark = Face::Glyphs.levels(glyphs, "dark")
    assert_equal 0.0, dark.first
    assert_in_delta 1.0, dark.last, 1e-12
    dark.each_cons(2) { |a, b| assert_operator b, :>, a }
    light = Face::Glyphs.levels(Face::Glyphs.ramp(Face::Glyphs::DEFAULT_CHARS, "light"), "light")
    assert_equal 0.0, light.first
    assert_in_delta 1.0, light.last, 1e-12
    light.each_cons(2) { |a, b| assert_operator b, :>, a }
    assert_equal [0.0, 0.5, 1.0], Face::Glyphs.levels(%w[1 2 3], "dark"), "an unmeasured ramp takes even steps"
  end

  def test_a_tone_is_quantised_in_ink_space_between_its_two_glyphs
    levels = Face::Glyphs.levels(Face::Glyphs::DEFAULT_CHARS.chars)
    levels.each_with_index { |level, i| assert_equal i, Face::Glyphs.index(level, levels, 0, 0) }
    assert_equal 0, Face::Glyphs.index(-1.0, levels, 1, 1)
    assert_equal levels.size - 1, Face::Glyphs.index(2.0, levels, 1, 1)
    tone = levels[7] + ((levels[8] - levels[7]) * 0.5)
    picks = (0..3).flat_map { |r| (0..3).map { |c| Face::Glyphs.index(tone, levels, c, r) } }
    assert_equal [7, 8], picks.uniq.sort
    low = levels[7] + ((levels[8] - levels[7]) * 0.1)
    high = levels[7] + ((levels[8] - levels[7]) * 0.9)
    count = ->(t) { (0..3).flat_map { |r| (0..3).map { |c| Face::Glyphs.index(t, levels, c, r) } }.count(8) }
    assert_operator count.call(low), :<, count.call(tone)
    assert_operator count.call(tone), :<, count.call(high)
  end

  def test_the_cheaper_path_takes_fewer_samples_on_a_big_window
    assert_equal Face::Ascii::SAMPLES, Face::Ascii.samples_for(28, 64)
    assert_equal Face::Ascii::LARGE.fetch("samples"), Face::Ascii.samples_for(100, 240)
    assert_operator Face::Ascii.samples_for(100, 240), :<, Face::Ascii::SAMPLES
  end

  def test_the_mesh_grows_with_the_window
    small = Face::Head.for(28, 64)
    large = Face::Head.for(60, 160)
    assert_operator large.rings, :>, small.rings
    assert_operator large.around, :>, small.around
  end

  def test_large_golden_frames_are_in_the_fixtures_and_plain_ascii
    sizes = FIXTURES.fetch("cases").map { |c| [c["rows"], c["cols"]] }
    assert_includes sizes, [60, 160]
    assert_includes sizes, [100, 240]
    FIXTURES.fetch("cases").select { |c| c["rows"] >= 60 }.each do |c|
      assert_equal c["rows"], c["lines"].size
      assert c["lines"].all? { |l| l.size <= c["cols"] }
      assert_match PRINTABLE, c["lines"].join("\n")
    end
  end

  def test_a_large_frame_is_deterministic_and_plain_ascii
    look = Face::Pose.at(:idle, 1.0, 1)
    draw = -> { Face::Ascii.new(Face::Head.for(60, 160), 60, 160).render(look).lines }
    first = draw.call
    assert_equal first, draw.call
    assert_equal 60, first.size
    assert_match PRINTABLE, first.join("\n")
    assert_operator first.join.delete(" ").size, :>, 2000, "the head fills a large window"
  end

  def test_a_large_frame_fits_a_generous_time_budget
    look = Face::Pose.at(:idle, 1.0, 1)
    ascii = Face::Ascii.new(Face::Head.for(60, 160), 60, 160)
    ascii.render(look)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    ascii.render(look)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    assert_operator elapsed, :<, 2.0, "60x160 took #{(elapsed * 1000).round} ms"
  end

  def test_big_eyes_have_lids_and_a_small_face_keeps_its_small_eyes
    big = Face::Ascii.new(Face::Head.for(60, 160), 60, 160).render(Face::Motion.rest).lines.join("\n")
    assert_match(/\.-{8,}\./, big, "an upper lid")
    assert_match(/\(\s{9,}O\s*\s*\)|\(\s+O\s+\)/, big, "a wide eye with its large pupil")
    small = Face::Ascii.new(Face::Head.for(28, 64), 28, 64).render(Face::Motion.rest).lines.join("\n")
    assert_includes small, "(   o   )"
    refute_includes small, "O"
  end
end
