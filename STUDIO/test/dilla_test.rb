# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "open3"
require "rbconfig"
require "tmpdir"
require_relative "../dilla/dilla"

# dilla is one Ruby file, one data file and a README. These tests hold the data to the shape
# the engine reads, the voicer to the chord names it is given, the timing to its clamp, and the
# engine itself to a smoke render in a temporary directory, so a run leaves nothing in the tree.
class DillaTest < Minitest::Test
  DIR = File.expand_path("../dilla", __dir__)
  SCRIPT = File.join(DIR, "dilla.rb")
  DATA = JSON.parse(File.read(File.join(DIR, "dilla.json")))
  PROGRESSIONS = DATA.fetch("progressions")
  CHORDS = PROGRESSIONS.flatten.uniq

  def run_dilla(*args, chdir:)
    Open3.capture3(RbConfig.ruby, SCRIPT, *args, chdir:)
  end

  def sequencer(profile, pd_amount: nil, seed: 5, data: DATA)
    Sequencer.new(data, profile_name: profile, pd_amount:, seed:)
  end

  def offsets_from_grid(hits, role, step)
    hits.select { |r, _| r == role }.map { |_, t| t - ((t / step).round * step) }
  end

  # ------------------------------------------------------------- the files

  def test_the_tracked_tree_is_the_engine_its_data_and_a_readme
    tracked, status = Open3.capture2("git", "ls-files", ".", chdir: DIR)
    skip "not a git checkout" unless status.success?
    assert_equal %w[.gitignore README.md dilla.json dilla.rb], tracked.lines.map(&:strip).sort
  end

  def test_no_artist_band_song_or_book_is_named_anywhere
    banned = /slum|village|madlib|lotus|flylo|coltrane|miles davis|hancock|herbie|jamal|d'angelo|badu|\bsade\b|stevie|marvin|gaye|thundercat|questlove|voodoo|donuts|fantastic|charnas|ethan hein|burton|theseus|james brown|mayfield|j dilla|jay dee|eddie harris|bill evans/i
    %w[dilla.rb dilla.json README.md].each do |file|
      text = File.read(File.join(DIR, file))
      assert_nil text[banned], "#{file} names #{text[banned].inspect}"
    end
  end

  def test_the_data_has_only_what_the_engine_reads
    assert_equal %w[drum_patterns groove_profiles progressions], DATA.keys.sort
  end

  # ------------------------------------------------------------- progressions

  def test_progressions_are_a_flat_array_of_chord_name_arrays_without_duplicates
    assert_operator PROGRESSIONS.size, :>, 90
    assert(PROGRESSIONS.all? { |p| p.is_a?(Array) && p.size >= 2 && p.all? { |c| c.is_a?(String) } })
    assert_equal PROGRESSIONS.map { |p| p.join(" ") }.uniq.size, PROGRESSIONS.size, "a spelling appears twice"
  end

  def test_every_chord_name_parses
    CHORDS.each { |name| Chords.parse(name) }
  end

  def test_the_voicer_reads_the_extended_chords_it_is_given
    assert_equal [0, 3, 7, 10, 14], Chords.parse("Cm9")[:tones]
    assert_equal [0, 4, 7, 11, 14], Chords.parse("Cmaj9")[:tones]
    assert_equal [0, 4, 7, 10, 14, 21], Chords.parse("C13")[:tones]
    assert_equal [0, 4, 7, 17], Chords.parse("Cadd11")[:tones]
    assert_equal [0, 5, 7, 10, 14], Chords.parse("C9sus4")[:tones]
    assert_equal [0, 3, 6, 10], Chords.parse("Cm7b5")[:tones]
    assert_equal [0, 4, 7, 10, 15], Chords.parse("C7#9")[:tones]
    parsed = Chords.parse("Bbm/E")
    assert_equal [10, 4], [parsed[:pc], parsed[:bass]]
    assert_raises(ArgumentError) { Chords.parse("H7") }
    assert_raises(ArgumentError) { Chords.parse("Cfoo") }
  end

  # Maps each voicing's pitch classes back to the chord spelling: nothing outside the chord and
  # its slash bass sounds, the lowest note is the root or the bass, and the third and the seventh
  # (the notes that make a chord what it is) are there when the chord has them.
  def test_every_voicing_maps_back_to_its_chord_spelling
    CHORDS.each do |name|
      chord = Chords.parse(name)
      bass_pc = chord[:bass] || chord[:pc]
      chord_pcs = chord[:tones].map { |t| (chord[:pc] + t) % 12 }
      [60, 64, 70].each do |centre|
        notes, = Chords.voice(name, centre)
        upper = notes.drop(1)
        assert_equal bass_pc, notes.first % 12, "#{name}: the lowest note is the root or the slash bass"
        assert_operator notes.first, :<, 48, "#{name}: the bass is in the low octave"
        assert(notes.all? { |n| (chord_pcs + [bass_pc]).include?(n % 12) }, "#{name}: #{notes} has a note the spelling does not")
        chord[:tones].select { |t| [2, 3, 4, 5, 10, 11].include?(t) }.each do |semi|
          assert_includes upper.map { |n| n % 12 }, (chord[:pc] + semi) % 12, "#{name}: no tone #{semi} above the root"
        end
        assert(upper.all? { |n| n.between?(52, 91) }, "#{name}: upper structure out of range #{notes}")
        assert(upper.each_cons(2).none? { |a, b| b - a == 1 }, "#{name}: a minor second rubs")
      end
    end
  end

  def test_slash_chords_put_the_bass_note_in_the_low_octave
    notes, = Chords.voice("Db/E")
    assert_equal 4, notes.first % 12
    assert_equal [1, 5, 8], notes.drop(1).map { |n| n % 12 }.sort
  end

  def test_voice_leading_moves_each_chord_close_to_the_last
    centres = Chords.midi_notes(%w[Cm9 Fm9 Bbm9 Ebmaj9]).map { |n| n.drop(1).sum / (n.size - 1) }
    centres.each_cons(2) { |a, b| assert_operator (a - b).abs, :<=, 7 }
  end

  # ------------------------------------------------------------- profiles and patterns

  def test_every_pattern_is_rows_of_sixteen_steps
    DATA.fetch("drum_patterns").each do |id, pattern|
      rows = pattern.select { |_, v| v.is_a?(Array) }
      assert_equal %w[hat kick snare], rows.keys.sort, id
      rows.each_value { |row| assert_equal 16, row.size, id }
    end
  end

  def test_the_inversion_pattern_has_no_kick_on_one
    inversion = DATA.fetch("drum_patterns").fetch("offbeat_inversion")
    on = ->(row) { inversion[row].each_index.select { |i| inversion[row][i] == 1 } }
    assert_equal [7, 12], on.("kick")
    assert_equal [4, 12], on.("snare")
    assert_equal [2, 6, 10, 14], on.("hat")
  end

  def test_every_profile_offset_is_inside_the_window
    DATA.fetch("groove_profiles").each do |id, profile|
      (profile["offsets"] || {}).each_value { |v| assert_operator v.abs, :<=, MAX_OFFSET, id }
      assert_operator profile.fetch("pd_amount", 1.0), :<=, 1.5, id
      assert_operator (profile["sidechain"] || {}).fetch("amount", 0.0), :<=, 1.0, id
    end
  end

  def test_the_sidechain_is_off_unless_a_profile_asks
    assert_equal %w[pump], DATA.fetch("groove_profiles").select { |_, p| p.key?("sidechain") }.keys
  end

  # ------------------------------------------------------------- timing

  def test_the_pattern_loops_across_the_whole_progression
    bar = 60.0 / 88 * 4
    hits = sequencer("dry").drum_hits("boom_bap", 88.0, bar * 6)
    assert_equal [0, 1, 2, 3, 4, 5], hits.map { |_, t| (t / bar).floor }.uniq.sort
    assert_equal 12, hits.count { |role, _| role == "snare" }
  end

  def test_pd_amount_zero_is_the_grid
    step = 60.0 / 88 / 4
    hits = sequencer("early_snare_late_hats", pd_amount: 0.0).drum_hits("syncopated_swing", 88.0, 8.0)
    hits.each { |_, t| assert_in_delta 0.0, (t / step) - (t / step).round, 1e-6 }
  end

  def test_the_early_snare_late_kick_direction_and_the_window
    step = 60.0 / 88 / 4
    hits = sequencer("early_snare_late_hats").drum_hits("syncopated_swing", 88.0, 40.0)
    snare = offsets_from_grid(hits, "snare", step)
    kick = offsets_from_grid(hits, "kick", step)
    assert_operator snare.sum / snare.size, :<, 0, "the snare sits early"
    assert_operator kick.sum / kick.size, :>, 0, "the kicks sit late"
    assert((snare + kick + offsets_from_grid(hits, "hat", step)).all? { |o| o.abs <= MAX_OFFSET + 1e-9 }, "swing and offset together stay in the window")
  end

  def test_the_first_kick_takes_its_own_offset
    hits = sequencer("early_snare_late_hats").drum_hits("syncopated_swing", 88.0, 12.0)
    assert_in_delta 0.0, hits.find { |r, _| r == "kick" }.last, 1e-9
    later = hits.select { |r, _| r == "kick" }[1]
    refute_in_delta 0.0, later.last % (60.0 / 88 / 4), 1e-4
  end

  def test_pd_amount_scales_the_pull_from_the_grid
    step = 60.0 / 88 / 4
    mean = lambda do |amount|
      hits = sequencer("behind_the_beat", pd_amount: amount, seed: 3).drum_hits("boom_bap", 88.0, 20.0)
      offs = offsets_from_grid(hits, "snare", step).map(&:abs)
      offs.sum / offs.size
    end
    assert_operator mean.call(1.5), :>, mean.call(1.0)
    assert_operator mean.call(1.0), :>, mean.call(0.5)
    assert_equal 1.5, sequencer("dry", pd_amount: 9.0).pd_amount
  end

  def test_drunk_sixteenths_are_seeded_and_never_past_the_window
    a = sequencer("dry", seed: 11).drum_hits("drunk_16ths", 88.0, 20.0)
    assert_equal a, sequencer("dry", seed: 11).drum_hits("drunk_16ths", 88.0, 20.0)
    refute_equal a, sequencer("dry", seed: 12).drum_hits("drunk_16ths", 88.0, 20.0)
    step = 60.0 / 88 / 4
    assert(a.all? { |_, t| (t - ((t / step).round * step)).abs <= MAX_OFFSET + 1e-9 })
    assert_operator a.count { |r, _| r == "hat" }, :>, 100, "all sixteenths hit"
  end

  def test_swing_is_per_role_and_takes_the_off_beat_eighths
    data = JSON.parse(JSON.generate(DATA))
    data["groove_profiles"]["probe"] = { "drum_swing" => { "hat" => 0.55, "kick" => 0.5 } }
    step = 60.0 / 88 / 4
    hits = sequencer("probe", data:).drum_hits("boom_bap", 88.0, 8.0)
    assert(offsets_from_grid(hits, "kick", step).all? { |o| o.abs < 1e-9 }, "the kick stays on the grid")
    late = hits.select { |r, t| r == "hat" && ((t / step).round % 4) == 2 }.map { |_, t| t - ((t / step).round * step) }
    refute_empty late
    late.each { |o| assert_in_delta 0.05 * 2 * 2 * step, o, 1e-4 }
  end

  # ------------------------------------------------------------- the sidechain

  def test_the_pump_ducks_the_chords_on_a_kick_and_other_profiles_do_not
    buf = Array.new(SAMPLE_RATE, 0.5)
    hits = [["kick", 0.1]]
    ducked = sequencer("pump").duck(buf, hits)
    start = (0.1 * SAMPLE_RATE).to_i
    assert_operator ducked[start], :<, buf[start] * 0.6
    assert_operator ducked[start + (0.5 * SAMPLE_RATE).to_i], :>, 0.47
    assert_equal buf, sequencer("lush").duck(buf, hits)
    assert_equal buf, sequencer("pump").duck(buf, [["snare", 0.1]])
  end

  # ------------------------------------------------------------- MIDI

  def read_midi(path)
    bytes = File.binread(path)
    assert_equal "MThd", bytes.byteslice(0, 4)
    assert_equal [0, 1, 480], bytes.byteslice(8, 6).unpack("nnn")
    assert_equal "MTrk", bytes.byteslice(14, 4)
    track = bytes.byteslice(22, bytes.byteslice(18, 4).unpack1("N"))
    events = []
    pos = 0
    tick = 0
    while pos < track.bytesize
      delta = 0
      loop do
        byte = track.getbyte(pos)
        pos += 1
        delta = (delta << 7) | (byte & 0x7f)
        break if byte < 0x80
      end
      tick += delta
      status = track.getbyte(pos)
      if status == 0xFF
        events << [tick, :meta, track.getbyte(pos + 1)]
        pos += 3 + track.getbyte(pos + 2)
      else
        events << [tick, status, track.getbyte(pos + 1), track.getbyte(pos + 2)]
        pos += 3
      end
    end
    events
  end

  def test_midi_export_rereads_as_the_chords_and_the_drums
    Dir.mktmpdir do |dir|
      names = %w[Cm9 Fm9 Bbm9]
      hits = sequencer("early_snare_late_hats").drum_hits("syncopated_swing", 88.0, 3 * 4 * 60.0 / 88)
      path = File.join(dir, "x.mid")
      MIDI.write(path, names, 88.0, 4.0, hits)
      events = read_midi(path)
      assert_equal [:meta, 0x2F], events.last[1, 2]
      ons = events.select { |e| e[1].is_a?(Integer) && (e[1] & 0xf0) == 0x90 }
      assert_equal Chords.midi_notes(names).flatten.sort, ons.select { |e| e[1] == 0x90 }.map { |e| e[2] }.sort
      drums = ons.select { |e| e[1] == 0x99 }
      assert_equal hits.size, drums.size
      assert_equal [36, 38, 42], drums.map { |e| e[2] }.uniq.sort
      assert_equal events.map(&:first), events.map(&:first).sort, "ticks never run backwards"
      offs = events.select { |e| e[1].is_a?(Integer) && (e[1] & 0xf0) == 0x80 }
      assert_equal ons.size, offs.size, "every note that starts also ends"
    end
  end

  # ------------------------------------------------------------- the command

  def test_list_prints_the_index_and_the_chords
    out, err, status = run_dilla("--list", chdir: Dir.tmpdir)
    assert status.success?, err
    assert_match(/^Progressions:\n\s+0  #{Regexp.escape(PROGRESSIONS.first.join(' '))}\n/, out)
    assert_includes out, "Drum patterns: #{DATA['drum_patterns'].keys.join(', ')}"
    assert_includes out, "Groove profiles: #{DATA['groove_profiles'].keys.join(', ')}"
  end

  def test_a_render_is_a_16_bit_mono_wav_the_same_seed_repeats_and_it_is_not_silent
    Dir.mktmpdir do |dir|
      a = File.join(dir, "a.wav")
      b = File.join(dir, "b.wav")
      args = ["--progression", "7", "--drums", "offbeat_inversion", "--profile", "pump", "--seed", "3", "--beats", "2",
              "--midi", File.join(dir, "a.mid")]
      [a, b].each do |out|
        _o, err, status = run_dilla(*args, "--out", out, chdir: dir)
        assert status.success?, err
      end
      assert_equal File.binread(a), File.binread(b)
      bytes = File.binread(a)
      assert_equal "RIFF", bytes.byteslice(0, 4)
      assert_equal [1, 44_100], [bytes.byteslice(22, 2).unpack1("v"), bytes.byteslice(24, 4).unpack1("V")]
      assert_operator bytes.byteslice(44..).unpack("s<*").map(&:abs).max, :>, 1000
      assert File.file?(File.join(dir, "a.mid"))
    end
  end

  def test_quick_renders_the_first_progression_to_out_in_the_working_directory
    Dir.mktmpdir do |dir|
      _out, err, status = run_dilla("--quick", chdir: dir)
      assert status.success?, err
      assert File.file?(File.join(dir, "out", "quick.wav"))
    end
  end

  def test_an_unknown_progression_pattern_or_profile_is_refused
    Dir.mktmpdir do |dir|
      out = File.join(dir, "x.wav")
      [%w[--progression 9999], %w[--progression 0 --drums nope], %w[--progression 0 --profile nope]].each do |args|
        _o, _e, status = run_dilla(*args, "--out", out, chdir: dir)
        refute status.success?, args.join(" ")
      end
    end
  end
end
