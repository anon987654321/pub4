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

        /''''''\
       ////--\\\\
      ///yX/\;:\\\
     |--------------
     |(  o  |(  o  )
     |||e///|\\~|||
      \\\\\-./////
      \\\       //
       \\\-----//

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
    # The heredoc stops at the last drawn row; the twelfth row is blank.
    assert_equal GOLDEN.each_line(chomp: true).to_a + [""], head_frame(12, 24, Face::Motion.rest).lines
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

  def test_the_human_parameters_are_the_head_and_a_tiny_mix_is_almost_it
    head = Face::Head.for(20, 40)
    assert_same head.mesh, Face::Masks.source(head, "baining", 0.0)
    assert_same head.mesh("baining"), Face::Masks.source(head, "baining", 1.0)
    near = Face::Masks.source(head, "baining", 1.0e-6)
    near.pos.each_with_index { |v, i| assert_in_delta head.mesh.pos[i], v, 1.0e-6 }
    refute_equal head.mesh.pos, head.mesh("baining").pos
  end

  # Every undirected edge with the number of triangles that use it.
  def edge_counts(mesh) = mesh.tris.each_slice(3).flat_map { |a, b, c| [[a, b], [b, c], [c, a]].map(&:minmax) }.tally

  def test_the_head_is_a_closed_mesh_wound_outward_with_the_same_topology_under_every_mask
    [[20, 40], [28, 64], [44, 140]].each do |rows, cols|
      head = Face::Head.for(rows, cols)
      assert_operator head.mesh.triangle_count, :>=, 3000
      [nil, *Face::Masks::ORDER].each do |mask|
        mesh = head.mesh(mask)
        assert_equal [2], edge_counts(mesh).values.uniq, "#{mask.inspect} at #{rows}x#{cols}: every edge has two triangles"
        assert_operator mesh.volume, :>, 0.0, "#{mask.inspect} at #{rows}x#{cols}: outward"
        assert_same head.mesh.tris, mesh.tris, "one topology"
        assert_equal head.mesh.vertex_count, mesh.vertex_count
        mesh.pos.each { |v| assert_predicate v, :finite? }
      end
      [0.3, 0.7].each { |mix| Face::Masks::ORDER.each { |m| assert_equal head.mesh.vertex_count, Face::Masks.source(head, m, mix).vertex_count } }
    end
  end

  def test_the_mesh_is_deterministic_and_the_landmarks_stand_on_the_face
    a = Face::Head.new(28, 64).mesh
    b = Face::Head.new(28, 64).mesh
    assert_equal a.pos, b.pos
    assert_equal a.landmarks, b.landmarks
    lm = a.landmarks
    assert_operator lm[:tip][2], :>, lm[:bridge][2], "the nose stands out of the brow"
    assert_operator lm[:tip][2], :>, lm[:mouth][:centre][2]
    lm[:eyes].each { |e| assert_operator e[:pupil][0].abs, :>, 0.05 }
    assert_operator lm[:eyes][0][:pupil][0], :<, 0.0
    assert_operator lm[:eyes][1][:pupil][0], :>, 0.0
  end

  CUBE_OBJ = FIXTURES.dig("meshes", "cube")

  # The cube faces the camera: the front face, wound inward in the file, is turned
  # outward and hides every other face, so it alone covers samples, and covers
  # exactly the square the camera maths puts there. Flat light means one luminance.
  def test_the_rasteriser_covers_a_unit_cube_by_the_square_the_camera_gives_it
    mesh = Face::Mesh.parse(CUBE_OBJ)
    assert_operator mesh.volume, :>, 0.0, "an inward wound file is turned outward"
    ascii = Face::Ascii.new(mesh, 30, 40)
    ascii.render(Face::Motion.rest)
    covered = ascii.instance_variable_get(:@tri).count { |t| t >= 0 }
    k = ascii.scale * Face::Ascii::CAMERA / (Face::Ascii::CAMERA - 1.0)
    side = 2 * k * Face::Ascii::SAMPLES
    assert_in_delta side * side, covered, side * side * 0.03
    lums = ascii.instance_variable_get(:@lum).each_index.select { |i| ascii.instance_variable_get(:@tri)[i] >= 0 }.map { |i| ascii.instance_variable_get(:@lum)[i] }
    assert_in_delta lums.min, lums.max, 1.0e-9, "a flat face is lit evenly"
  end

  def test_a_triangle_covers_its_area_and_back_faces_are_culled
    tri = "v -1 -1 0\nv 1 -1 0\nv 0 1 0\nf 1 2 3\n"
    mesh = Face::Mesh.parse(tri)
    ascii = Face::Ascii.new(mesh, 20, 40)
    covered = lambda do |m|
      a = Face::Ascii.new(m, 20, 40)
      a.render(Face::Motion.rest)
      a.instance_variable_get(:@tri).count { |t| t >= 0 }
    end
    n = covered.call(mesh)
    # An open triangle has no inside, so its volume is zero and it stays as read.
    expected = 0.5 * 2 * 2 * ((ascii.scale * Face::Ascii::SAMPLES)**2)
    assert_in_delta expected, n, expected * 0.06
    flipped = Face::Mesh.new(mesh.pos, [0, 2, 1], mesh.bright)
    assert_equal 0, covered.call(flipped), "seen from behind it is culled"
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
    assert_match(/-{10,}/, maprik, "the halo")
    assert_match(/'{8,}/, maprik, "the halo's second row")
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

  def test_idle_motion_holds_a_stable_face_and_particle_cloud
    motion = Face::Motion.new(seed: 7)
    first = motion.step(state: :idle, t: 1.0, count: 24)
    later = motion.step(state: :idle, t: 8.0, count: 24)

    assert_equal first, later
    assert_equal 1.0, later.scale
    assert_equal 0.0, later.bob
    assert_equal Master::CLI::Face::Motion::LIGHT.fetch("start"), later.light
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
    with_env(MASTER_FACE_QUIET: "1") { assert_equal "thinking", thinking.call.lines.map(&:strip).reject(&:empty?).first }
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
    assert_equal Face::Glyphs::DEFAULT_CHARS.chars, Face::Glyphs.ramp
    assert_equal " .:;=*%#@".reverse.chars, Face::Glyphs.ramp(" .:;=*%#@", "light")
    assert_equal %w[M A S T E R], Face::Glyphs.ramp("MASTER")
    frame = Face::Ascii.new(Face::Head.for(14, 30), 14, 30, chars: "MASTER").render(Face::Motion.rest)
    assert_empty frame.lines.join.delete("MASTER|/\x27_o().() ").delete("\\").delete("-")
  end

  def test_the_ramp_is_ordered_by_measured_ink
    ascii = Master::Face::Contract.ascii
    ink = ascii.fetch("ink")
    glyphs = ascii.fetch("chars").chars
    assert_equal glyphs.sort, ink.keys.sort
    glyphs.each_cons(2) { |a, b| assert_operator ink.fetch(b), :>, ink.fetch(a), "#{b.inspect} is inkier than #{a.inspect}" }
    assert_equal 0.0, ink.fetch(" ")
  end

  def test_the_key_light_orbits_and_is_part_of_the_pose
    light = Master::Face::Contract.ascii.fetch("light")
    assert_equal light.fetch("start"), Face::Pose.at(:idle, 0.0, 1).light
    assert_in_delta light.fetch("start") + (light.fetch("orbit") * 4.0), Face::Pose.at(:idle, 4.0, 1).light, 1e-12
    assert_equal Face::Pose.at(:speaking, 2.5, 3), Face::Pose.at(:speaking, 2.5, 3)
    a = head_frame(28, 64, Face::Motion.rest(turn: 0.5, light: 0.0)).lines
    b = head_frame(28, 64, Face::Motion.rest(turn: 0.5, light: 2.5)).lines
    refute_equal a, b
    assert_equal a, head_frame(28, 64, Face::Motion.rest(turn: 0.5, light: 0.0)).lines
  end

  def test_reduced_motion_holds_the_light_too
    with_env(MASTER_REDUCED_MOTION: "1") do
      motion = Face::Motion.new
      assert_equal Face.frame(state: :idle, rows: 20, cols: 40, t: 0.1, motion:), Face.frame(state: :idle, rows: 20, cols: 40, t: 9.0, motion:)
    end
  end

  def test_dither_is_fixed_in_screen_space
    levels = Face::Glyphs.levels(Face::Glyphs::DEFAULT_CHARS.chars)
    tone = (levels[10] + levels[11]) / 2
    assert_equal Face::Glyphs.index(tone, levels, 3, 2), Face::Glyphs.index(tone, levels, 3 + 4, 2 + 4)
    picks = (0..3).flat_map { |r| (0..3).map { |c| Face::Glyphs.index(tone, levels, c, r) } }
    assert_equal [10, 11], picks.uniq.sort, "a tone between two glyphs is dithered between exactly those two"
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

  def test_features_on_the_far_side_of_the_head_are_not_drawn
    back = head_frame(28, 64, Face::Motion.rest(turn: Math::PI)).lines
    text = back.join("\n")
    refute_includes text, "(", "no eyes on the back of the head"
    refute_includes text, "o"
    assert_operator back.join.delete(" ").size, :>, 200, "the back is still a lit solid"
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
    with_env(MASTER_FACE_QUIET: "1") do
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
    assert_equal 12, mesh.triangle_count
    xs = mesh.pos.each_slice(3).map(&:first)
    assert_in_delta 0.0, xs.minmax.sum, 1e-9, "centred"
    frame = Face::Ascii.new(mesh, 14, 30).render(Face::Motion.rest(turn: 0.6, pitch: 0.3))
    assert_operator frame.lines.join.delete(" ").size, :>, 60
    assert_match PRINTABLE, frame.to_s
  end

  def test_obj_quads_are_split_into_triangles
    mesh = Face::Mesh.parse(FIXTURES.dig("meshes", "cube"))
    assert_equal 12, mesh.triangle_count
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

  # The art stops at the face; the three shell glyphs the CLI and web share are the one token set left over.
  def test_ascii_art_contract_is_limited_to_the_face_renderer
    ascii = Master::Face::Contract.ascii
    refute ascii.key?("wordmark")
    assert_equal %w[input continuation output], ascii.fetch("prompt").keys
    refute_respond_to Master::Face::Contract, :wordmark
    refute_respond_to Master::CLI::BootBanner, :wordmark
  end

  def test_cli_log_quiet_does_not_suppress_the_face
    with_env(MASTER_CLI_QUIET: "1", MASTER_FACE_QUIET: "0") do
      frame = Face.frame(state: :idle, rows: 24, cols: 60, t: 0.0)
      assert_operator frame.lines.map(&:strip).reject(&:empty?).length, :>, 1
    end
  end
end
