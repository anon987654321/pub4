# frozen_string_literal: true

require_relative "test_helper"
require "json"

# The plain-ASCII terminal face: contours, shading, features, depth and the
# fixtures the web port asserts against.
class TestCliAsciiFace < Minitest::Test
  Face = Master::CLI::Face
  FIXTURES = JSON.parse(File.read(File.join(__dir__, "fixtures", "face_ascii_frames.json")))
  PRINTABLE = /\A[\x20-\x7e\n]*\z/
  # A front frame at 12 rows by 24 columns with the head at rest.
  GOLDEN = <<-'FRAME'
      //''''''''\\
     /:-=+*++==-:.\
     |:-=++++=--:.|
     |-=++*+|==-:.|
     |------|-----|
    |:-( o )|( o ):|
    |-=++***|+==--:|
    |:==****.+=--:.|
    \\:--      :..//
      \\:.----..//
        \      /
           ---
  FRAME

  def head_frame(rows, cols, look, state: :idle)
    Face::Ascii.new(Face::Head.for(rows, cols), rows, cols, chars: Face::Glyphs::DEFAULT_CHARS, mode: "dark").render(look, state:)
  end

  def with_env(**vars)
    old = vars.keys.to_h { |k| [k, ENV.fetch(k.to_s, nil)] }
    vars.each { |k, v| ENV[k.to_s] = v }
    yield
  ensure
    old.each { |k, v| ENV[k.to_s] = v }
  end

  def test_golden_frame_is_exact
    assert_equal GOLDEN.lines.map(&:rstrip), head_frame(12, 24, Face::Motion.rest).lines
  end

  def test_every_fixture_frame_is_reproduced_and_plain_ascii
    FIXTURES.fetch("cases").each do |c|
      src = c.dig("source", "kind") == "head" ? Face::Head.for(c["rows"], c["cols"]) : Face::Mesh.parse(FIXTURES.dig("meshes", c.dig("source", "ref")))
      ascii = Face::Ascii.new(src, c["rows"], c["cols"], chars: FIXTURES["chars"], mode: "dark")
      frame = ascii.render(Face::Pose.at(c["state"].to_sym, c["t"], c["seed"]), state: c["state"].to_sym)
      assert_equal c["digest"], ascii.digest, "#{c["name"]}: points changed"
      assert_equal c["lines"].map(&:rstrip), frame.lines, c["name"]
      assert_match PRINTABLE, frame.to_s, c["name"]
    end
  end

  def mask_frame(rows, cols, mask, mix, look: Face::Pose.at(:idle, 0.0, 1))
    src = Face::Masks.source(Face::Head.for(rows, cols), mask, mix)
    Face::Ascii.new(src, rows, cols, chars: Face::Glyphs::DEFAULT_CHARS, mode: "dark").render(look)
  end

  def test_every_mask_fixture_frame_is_reproduced_and_plain_ascii
    cases = FIXTURES.fetch("masks")
    assert_equal Face::Masks::ORDER.size * 4, cases.size
    cases.each do |c|
      src = Face::Masks.source(Face::Head.for(c["rows"], c["cols"]), c["mask"], c["mix"])
      ascii = Face::Ascii.new(src, c["rows"], c["cols"], chars: FIXTURES["chars"], mode: "dark")
      frame = ascii.render(Face::Pose.at(c["state"].to_sym, c["t"], c["seed"]), state: c["state"].to_sym)
      assert_equal c["digest"], ascii.digest, "#{c["name"]}: points changed"
      assert_equal c["lines"].map(&:rstrip), frame.lines, c["name"]
      assert_match PRINTABLE, frame.to_s, c["name"]
    end
  end

  def test_the_fixture_trigger_section_is_reproduced
    trigger = FIXTURES.fetch("trigger")
    trigger["picks"].each { |session, mask| assert_equal mask, Face::Masks.pick(session), session.inspect }
    trigger["mixes"].each do |m|
      assert_in_delta m["mix"], Face::Masks.mix(m["state"].to_sym, m["t"], since: m["since"], from: m["from"]), 1e-15
    end
    trigger["morphs"].each do |mask, mid|
      assert_equal mid, Face::Masks.morph(Face::Masks.params(nil), Face::Masks.params(mask), 0.5)
    end
  end

  def test_morph_ends_are_exact_and_the_middle_is_deterministic
    human = Face::Masks.params(nil)
    Face::Masks::ORDER.each do |mask|
      target = Face::Masks.params(mask)
      assert_same human, Face::Masks.morph(human, target, 0.0)
      assert_same target, Face::Masks.morph(human, target, 1.0)
      assert_equal Face::Masks.morph(human, target, 0.37), Face::Masks.morph(human, target, 0.37)
      middle = Face::Masks.morph(human, target, 0.5)
      human.each_key { |k| assert_in_delta (human[k] + target[k]) / 2.0, middle[k], 1e-12, "#{mask} #{k}: smoothstep(0.5) is one half" }
    end
    assert_equal 0.0, Face::Masks.smoothstep(-1)
    assert_equal 1.0, Face::Masks.smoothstep(2)
    assert_in_delta 0.15625, Face::Masks.smoothstep(0.25), 1e-15
  end

  def test_the_human_parameters_rebuild_the_head_point_for_point
    head = Face::Head.for(20, 40)
    shape = Face::Masks::Shape.new(head, Face::Masks.params(nil))
    mine = []
    shape.each_point { |x, y, z, b, zone, *| mine << [x, y, z, b, zone] }
    theirs = []
    head.each_point { |x, y, z, b, zone, *| theirs << [x, y, z, b, zone] }
    assert_equal theirs, mine
    assert_same head, Face::Masks.source(head, "baining", 0.0)
  end

  def test_every_target_sits_on_the_same_lattice
    [[20, 40], [28, 64], [14, 30]].each do |rows, cols|
      head = Face::Head.for(rows, cols)
      Face::Masks::ORDER.each do |mask|
        [0.3, 1.0].each do |mix|
          count = 0
          Face::Masks.source(head, mask, mix).each_point { |*| count += 1 }
          assert_equal head.count, count, "#{mask} at #{rows}x#{cols}, mix #{mix}"
        end
      end
    end
  end

  def test_the_five_masks_differ_from_each_other_and_from_the_head
    plain = head_frame(28, 64, Face::Pose.at(:idle, 0.0, 1)).lines
    frames = Face::Masks::ORDER.to_h { |m| [m, mask_frame(28, 64, m, 1.0).lines] }
    frames.each { |m, f| refute_equal plain, f, m }
    assert_equal frames.size, frames.values.uniq.size
    assert_equal plain, mask_frame(28, 64, "maprik_yam", 0.0).lines
    frames.each_value { |f| assert_match PRINTABLE, f.join("\n") }
  end

  def test_each_extra_feature_reads_in_plain_ascii
    maprik = mask_frame(28, 64, "maprik_yam", 1.0).lines.join("\n")
    assert_match(/OO+/, maprik, "ring eyes")
    assert_match(/-----'+-----/, maprik, "the halo")
    assert_includes maprik, "\\_/", "the beak's tip"
    assert_match(/=====/, mask_frame(28, 64, "iatmul_mei", 1.0).lines.join("\n"), "heavy brow")
    sepik = mask_frame(28, 64, "sepik_woven", 1.0).lines
    assert sepik.any? { |l| l.start_with?("  ") && l.lstrip.start_with?("OOO") }, "ear discs stand outside the head"
    gourd = mask_frame(28, 64, "highlands_gourd", 1.0).lines.join("\n")
    assert_includes gourd, "(   o   )", "the gourd keeps its eyes and little else"
    refute_includes gourd, "\\_/"
  end

  def test_the_mask_follows_thinking_only
    mix = ->(state, t, since: 0.0, from: 0.0) { Face::Masks.mix(state, t, since:, from:) }
    Face::STATES.reject { |s| s == :thinking }.each { |s| assert_equal 0.0, mix.call(s, 5.0), s.to_s }
    assert_equal 0.0, mix.call(:thinking, 0.0)
    assert_in_delta 0.5, mix.call(:thinking, 0.6), 1e-12
    assert_equal 1.0, mix.call(:thinking, 1.2)
    assert_equal 1.0, mix.call(:thinking, 60.0)
    assert_in_delta 0.5, mix.call(:idle, 0.4, from: 1.0), 1e-12
    assert_equal 0.0, mix.call(:speaking, 0.8, from: 1.0)
    assert_equal :thinking, Master::Face::Contract.ascii.dig("masks", "trigger_states").first.to_sym
  end

  def test_pose_carries_the_mask_only_when_asked
    assert_nil Face::Pose.at(:thinking, 2.0, 1).mask
    assert_equal 0.0, Face::Pose.at(:thinking, 2.0, 1).mix
    look = Face::Pose.at(:thinking, 2.0, 1, schedule: { session: "abc", since: 0.0 })
    assert_equal "iatmul_mei", look.mask
    assert_equal 1.0, look.mix
    assert_equal 0.0, Face::Pose.at(:idle, 2.0, 1, schedule: { session: "abc", since: 0.0 }).mix
  end

  def test_motion_eases_in_while_thinking_and_back_out_after
    motion = Face::Motion.new(session: "abc")
    mixes = [[:idle, 0.0], [:idle, 0.5], [:thinking, 1.0], [:thinking, 1.6], [:thinking, 2.3], [:thinking, 3.0], [:idle, 3.4], [:idle, 3.8], [:idle, 4.2]].map do |state, t|
      motion.step(state:, t:, count: 0).mix
    end
    assert_equal [0.0, 0.0], mixes.first(2)
    assert_in_delta 0.5, mixes[3], 1e-12
    assert_equal 1.0, mixes[5]
    assert_equal 1.0, mixes[6]
    assert_in_delta 0.5, mixes[7], 1e-12, "easing back out of a full mask takes ease.out seconds"
    assert_equal 0.0, mixes.last
    assert_equal "iatmul_mei", motion.step(state: :idle, t: 5.0, count: 0).mask
  end

  def test_the_frame_morphs_while_thinking_and_not_when_quiet_reduced_or_small
    thinking = lambda do |rows: 24, cols: 60, plain: false|
      motion = Face::Motion.new(session: "abc")
      motion.step(state: :idle, t: 0.0, count: 0)
      motion.step(state: :thinking, t: 1.0, count: 0)
      Face.frame(state: :thinking, rows:, cols:, t: 3.0, motion:, source: plain ? Face::Head.for(rows, cols) : nil)
    end
    refute_equal thinking.call(plain: true), thinking.call
    with_env(MASTER_REDUCED_MOTION: "1") { assert_equal thinking.call(plain: true), thinking.call }
    with_env(MASTER_CLI_QUIET: "1") { assert_equal "thinking", thinking.call.lines.map(&:strip).reject(&:empty?).first }
    assert_equal "thinking", thinking.call(rows: Face::MIN_ROWS - 1).lines.map(&:strip).reject(&:empty?).first
  end

  def test_no_braille_anywhere_in_the_face_sources_or_output
    sources = Dir[File.join(__dir__, "..", "lib", "cli", "face*"), File.join(__dir__, "..", "lib", "cli", "face", "*.rb")].select { |f| File.file?(f) }
    refute_empty sources
    sources.each { |f| refute_match(/[⠀-⣿]/, File.read(f), f) }
    refute_match(/[⠀-⣿]/, Face.frame(state: :speaking, rows: 24, cols: 60, t: 1.0, color: true))
  end

  def test_contour_glyphs_follow_the_cell_aspect
    assert_equal "-", Face::Glyphs.line(1, 0)
    assert_equal "|", Face::Glyphs.line(0, 1)
    assert_equal "/", Face::Glyphs.line(1, 1), "45 degrees leans like a slash on a cell twice as tall as wide"
    assert_equal "/", Face::Glyphs.line(1, 2)
    assert_equal "\\", Face::Glyphs.line(1, -1)
    assert_equal "\\", Face::Glyphs.line(-1, 1)
    assert_equal "-", Face::Glyphs.line(5, 1)
    assert_equal "|", Face::Glyphs.line(1, 6)
  end

  def test_horizontal_edges_pick_their_half_cell
    assert_equal "-", Face::Glyphs.level(true, false, true)
    assert_equal "-", Face::Glyphs.level(false, true, false)
    assert_equal "_", Face::Glyphs.level(true, true, true)
    assert_equal "'", Face::Glyphs.level(true, true, false)
  end

  def test_the_ramp_is_replaceable_and_inverts_in_light_mode
    assert_equal " .:-=+*#%@".chars, Face::Glyphs.ramp
    assert_equal "@%#*+=-:. ".chars, Face::Glyphs.ramp(" .:-=+*#%@", "light")
    assert_equal %w[M A S T E R], Face::Glyphs.ramp("MASTER")
    frame = Face::Ascii.new(Face::Head.for(14, 30), 14, 30, chars: "MASTER").render(Face::Motion.rest)
    assert_empty frame.lines.join.delete("MASTER|/\x27_o() ").delete("\\").delete("-")
  end

  def test_dither_is_fixed_in_screen_space
    assert_equal Face::Glyphs.index(0.5, 10, 3, 2), Face::Glyphs.index(0.5, 10, 3 + 4, 2 + 4)
    picks = (0..3).flat_map { |r| (0..3).map { |c| Face::Glyphs.index(0.5, 10, c, r) } }
    assert_operator picks.uniq.size, :>=, 2
  end

  def test_turning_does_not_shimmer
    a = head_frame(28, 64, Face::Motion.rest(turn: 1.000)).lines
    b = head_frame(28, 64, Face::Motion.rest(turn: 1.002)).lines
    cells = a.sum(&:size)
    changed = a.zip(b).sum { |x, y| x.ljust(64).chars.zip(y.ljust(64).chars).count { |p, q| p != q } }
    assert_operator changed.fdiv(cells), :<, 0.06
  end

  def test_speaking_and_listening_change_the_mouth_rows
    idle = head_frame(28, 64, Face::Motion.rest).lines
    speaking = head_frame(28, 64, Face::Motion.rest(mouth: 1.0, mouth_open: 1.0), state: :speaking).lines
    listening = head_frame(28, 64, Face::Motion.rest, state: :listening).lines
    mouth = 19..26
    refute_equal idle[mouth], speaking[mouth]
    refute_equal idle[mouth], listening[mouth]
    assert_match(%r{\\_+/}, listening[mouth].join("\n"))
    assert_match(/\.-+\./, speaking[mouth].join("\n"))
  end

  def test_blinking_closes_the_lids
    open = head_frame(28, 64, Face::Motion.rest).lines.join("\n")
    shut = head_frame(28, 64, Face::Motion.rest(eye_open: 0.0)).lines.join("\n")
    assert_includes open, "(   o   )"
    refute_includes shut, "(   o   )"
  end

  def test_small_windows_name_the_state
    text = Face.frame(state: :thinking, rows: Face::MIN_ROWS - 1, cols: 60, t: 0.0)
    assert_equal "thinking", text.lines.map(&:strip).reject(&:empty?).first
    text = Face.frame(state: :idle, rows: 20, cols: Face::MIN_COLS - 1, t: 0.0)
    assert_equal "idle", text.lines.map(&:strip).reject(&:empty?).first
  end

  def test_quiet_and_reduced_motion_flags
    with_env(MASTER_CLI_QUIET: "1") do
      assert_equal "idle", Face.frame(state: :idle, rows: 24, cols: 60, t: 0.0).lines.map(&:strip).reject(&:empty?).first
    end
    with_env(MASTER_REDUCED_MOTION: "1") do
      motion = Face::Motion.new
      a = Face.frame(state: :idle, rows: 20, cols: 40, t: 0.1, motion:)
      b = Face.frame(state: :idle, rows: 20, cols: 40, t: 0.3, motion:)
      assert_equal a, b
    end
  end

  def test_depth_marks_near_bold_and_far_dim
    colored = head_frame(20, 40, Face::Motion.rest).to_s(color: true)
    assert_match(/\e\[0;1;38/, colored)
    assert_match(/\e\[0;2;38/, colored)
    refute_includes head_frame(20, 40, Face::Motion.rest).to_s, "\e"
  end

  STL_CUBE = begin
    v = [[0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 1, 0], [0, 0, 1], [1, 0, 1], [1, 1, 1], [0, 1, 1]]
    faces = [[0, 2, 1], [0, 3, 2], [4, 5, 6], [4, 6, 7], [0, 1, 5], [0, 5, 4], [2, 3, 7], [2, 7, 6], [1, 2, 6], [1, 6, 5], [3, 0, 4], [3, 4, 7]]
    body = faces.map { |f| "facet normal 0 0 0\nouter loop\n#{f.map { |i| "vertex #{v[i].join(" ")}" }.join("\n")}\nendloop\nendfacet" }
    "solid cube\n#{body.join("\n")}\nendsolid cube\n"
  end

  def test_ascii_stl_reader_turns_a_tiny_cube_into_a_picture
    mesh = Face::Mesh.parse(STL_CUBE)
    assert_equal 12, mesh.triangles.size
    xs = mesh.triangles.flatten(1).map(&:first)
    assert_in_delta 0.0, xs.minmax.sum, 1e-9, "centred"
    frame = Face::Ascii.new(mesh, 14, 30).render(Face::Motion.rest(turn: 0.6, pitch: 0.3))
    assert_operator frame.lines.join.delete(" ").size, :>, 60
    assert_match PRINTABLE, frame.to_s
  end

  def test_obj_quads_are_split_into_triangles
    mesh = Face::Mesh.parse(FIXTURES.dig("meshes", "cube"))
    assert_equal 12, mesh.triangles.size
  end

  def test_the_pose_is_a_pure_function
    assert_equal Face::Pose.at(:idle, 2.0, 1), Face::Pose.at(:idle, 2.0, 1)
    assert_in_delta Face::Motion::SPIN * 2.0, Face::Pose.at(:idle, 2.0, 1).turn, 1e-12
    assert_in_delta 0.0, Face::Pose.at(:listening, 2.0, 1).turn, 1e-12
    assert_operator Face::Pose.at(:speaking, 1.35, 1).mouth, :>, 0.0
  end

  def test_the_renderer_reads_its_numbers_from_the_face_contract
    ascii = Master::Face::Contract.ascii
    assert_equal ascii.fetch("chars"), Face::Glyphs::DEFAULT_CHARS
    assert_equal ascii.fetch("aspect"), Face::Glyphs::ASPECT
  end
  def test_wordmark_is_line_art_and_prompt_glyphs_are_shared
    art = Master::Face::Contract.wordmark
    assert_equal 3, art.size
    assert_empty art.join.delete(" |/_-").delete("\\")
    assert_equal "|-", Master::Face::Contract.glyph(:input)
    assert_equal "\\_", Master::Face::Contract.glyph(:continuation)
    assert_equal "/", Master::Face::Contract.glyph(:output)
  end

  def test_wordmark_shows_only_on_an_interactive_terminal
    io = StringIO.new
    refute Master::CLI::BootBanner.wordmark(io:)
    assert_empty io.string
    tty = StringIO.new.tap { |o| o.define_singleton_method(:tty?) { true } }
    $stdin.stub(:tty?, true) do
      Master::CLI::BootBanner.instance_variable_set(:@wordmark_shown, false)
      assert Master::CLI::BootBanner.wordmark(io: tty)
      refute Master::CLI::BootBanner.wordmark(io: tty), "once only"
    end
    assert_includes tty.string, Master::Face::Contract.wordmark.first
  ensure
    Master::CLI::BootBanner.instance_variable_set(:@wordmark_shown, false)
  end
end
