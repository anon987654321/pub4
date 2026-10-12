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
  def test_ascii_art_contract_is_limited_to_the_face_renderer
    ascii = Master::Face::Contract.ascii
    refute ascii.key?("wordmark")
    refute ascii.key?("prompt")
    refute_respond_to Master::Face::Contract, :wordmark
    refute_respond_to Master::Face::Contract, :glyph
    refute_respond_to Master::CLI::BootBanner, :wordmark
  end
end
