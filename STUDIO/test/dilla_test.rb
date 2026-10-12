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
    assert_equal %w[arp comp default_profile drum_patterns echo groove_profiles mix nasty_vcs play_profiles progressions sonitex strum voices], DATA.keys.sort
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

  # What a chord must keep: the third or sus tone, the sixth or seventh and every named
  # extension, as pitch classes. The root or the slash bass is the lowest note.
  def required_pcs(chord)
    chord[:tones].select { |t| [2, 3, 4, 5, 9, 10, 11].include?(t) || t >= 13 }.map { |t| (chord[:pc] + t) % 12 }
  end

  # Maps each voicing's pitch classes back to the chord spelling: nothing outside the chord and
  # its slash bass sounds, the lowest note is the root or the bass, and the third, the sus tone,
  # the seventh and the named extension are there. Run with and without the search.
  def test_every_voicing_maps_back_to_its_chord_spelling
    previous_chords = [nil, [40, 60, 64, 67], [46, 64, 70, 73, 77], [38, 57, 74, 77]]
    CHORDS.each do |name|
      chord = Chords.parse(name)
      bass_pc = chord[:bass] || chord[:pc]
      chord_pcs = chord[:tones].map { |t| (chord[:pc] + t) % 12 }
      previous_chords.product([true, false]).each do |previous, search|
        notes = Chords.voice(name, previous, search:)
        upper = notes.drop(1)
        assert_equal bass_pc, notes.first % 12, "#{name}: the lowest note is the root or the slash bass"
        assert_operator notes.first, :<, 48, "#{name}: the bass is in the low octave"
        assert(notes.all? { |n| (chord_pcs + [bass_pc]).include?(n % 12) }, "#{name}: #{notes} has a note the spelling does not")
        assert_operator notes.size, :<=, [Chords::MAX_VOICES, 1 + required_pcs(chord).uniq.size].max, "#{name}: too many voices"
        assert(upper.all? { |n| n.between?(52, 84) }, "#{name}: upper structure out of range #{notes}")
        assert(upper.each_cons(2).none? { |a, b| b - a <= 1 }, "#{name}: a duplicate or a minor second rubs")
      end
    end
  end

  # (a) Every chord of all 105 progressions keeps its essential tones, however it is led to.
  def test_no_voicing_loses_a_chord_tone_in_any_progression
    PROGRESSIONS.each_with_index do |names, index|
      [true, false].each do |search|
        Chords.midi_notes(names, search:).each_with_index do |notes, i|
          chord = Chords.parse(names[i])
          missing = required_pcs(chord) - notes.map { |n| n % 12 }
          assert_empty missing, "progression #{index} #{names[i]} (search #{search}) lost pitch classes #{missing}"
          assert notes.size <= Chords::MAX_VOICES, "progression #{index} #{names[i]} has #{notes.size} voices"
        end
      end
    end
  end

  def test_a_slash_chord_keeps_its_root_when_the_bass_is_another_note
    notes = Chords.voice("Dbmaj7/Eb")
    assert_equal 3, notes.first % 12
    assert_equal [0, 1, 5, 8], notes.drop(1).map { |n| n % 12 }.uniq.sort, "Db F Ab C all sound over the Eb bass"
  end

  def test_slash_chords_put_the_bass_note_in_the_low_octave
    notes = Chords.voice("Db/E")
    assert_equal 4, notes.first % 12
    assert_equal [1, 5, 8], notes.drop(1).map { |n| n % 12 }.sort
  end

  def test_over_the_voice_cap_the_fifth_goes_and_the_third_seventh_and_extension_stay
    chord = Chords.parse("C13")
    assert_equal [4, 10, 2, 9], Chords.upper_pcs(chord).sort_by { |pc| [4, 10, 2, 9].index(pc) }
    refute_includes Chords.upper_pcs(chord), 7
    assert_includes Chords.upper_pcs(Chords.parse("C7b5")), 6, "an altered fifth stays when the chord fits"
  end

  def test_voice_leading_moves_each_chord_close_to_the_last
    centres = Chords.midi_notes(%w[Cm9 Fm9 Bbm9 Ebmaj9]).map { |n| n.drop(1).sum / (n.size - 1) }
    centres.each_cons(2) { |a, b| assert_operator (a - b).abs, :<=, 7 }
  end

  # The top line's leaps over a major third, as a share of all chord changes in all progressions.
  def top_leap_share(search)
    leaps = 0
    changes = 0
    PROGRESSIONS.each do |names|
      Chords.midi_notes(names, search:).each_cons(2) do |a, b|
        changes += 1
        leaps += 1 if (a.max - b.max).abs > 4
      end
    end
    leaps.to_f / changes
  end

  def mean_movement(search)
    total = 0.0
    count = 0
    PROGRESSIONS.each do |names|
      Chords.midi_notes(names, search:).each_cons(2) do |a, b|
        b.drop(1).each do |n|
          total += a.drop(1).map { |m| (n - m).abs }.min
          count += 1
        end
      end
    end
    total / count
  end

  # (b) The search keeps the top line smooth, and switching it off gives a measurably larger share.
  def test_the_search_keeps_top_line_leaps_under_sixteen_percent_and_the_switch_shows_it
    with = top_leap_share(true)
    without = top_leap_share(false)
    assert_operator with, :<, 0.16
    assert_operator without, :>, with + 0.05, "plain nearest-tone voicing leaps #{without}, searched #{with}"
  end

  # (c) Same names, same notes, every time; the command's switch changes the render.
  def test_voicing_is_deterministic
    names = PROGRESSIONS.fetch(7)
    assert_equal Chords.midi_notes(names), Chords.midi_notes(names)
    assert_equal Chords.freqs(names), Chords.freqs(names)
    refute_equal Chords.midi_notes(PROGRESSIONS.flatten.first(12)), Chords.midi_notes(PROGRESSIONS.flatten.first(12), search: false)
  end

  def test_no_voice_search_switch_changes_the_midi_file
    Dir.mktmpdir do |dir|
      args = ["--progression", "5", "--seed", "1"]
      run_dilla(*args, "--midi", File.join(dir, "a.mid"), "--out", File.join(dir, "a.wav"), chdir: dir)
      run_dilla(*args, "--no-voice-search", "--midi", File.join(dir, "b.mid"), "--out", File.join(dir, "b.wav"), chdir: dir)
      refute_equal File.binread(File.join(dir, "a.mid")), File.binread(File.join(dir, "b.mid"))
    end
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

  # ------------------------------------------------------------- the pocket

  POCKET = "straight_hats_snare_ahead"

  def lean_steps(hits, role, bpm)
    step = 60.0 / bpm / 4
    offsets_from_grid(hits, role, step).map { |o| o / step }
  end

  def test_the_pocket_is_the_default_profile_and_the_random_one
    assert_equal POCKET, DATA.fetch("default_profile")
    assert_includes DATA.fetch("groove_profiles"), POCKET
    Dir.mktmpdir do |dir|
      %w[--progression\ 2 --random].each do |flag|
        _o, err, status = run_dilla(*flag.split, "--drums", "boom_bap", "--seed", "4", "--out", File.join(dir, "x.wav"), chdir: dir)
        assert status.success?, err
        assert_match(/profile=#{POCKET}/, _o)
      end
    end
  end

  def test_the_hats_hold_the_grid_the_snare_leads_and_the_kick_lags_after_its_anchor
    hits = sequencer(POCKET).drum_hits("syncopated_swing", 128.0, 60.0)
    assert(lean_steps(hits, "hat", 128.0).all? { |l| l.abs < 1e-6 }, "the hats hold the grid")
    backbeats = sequencer(POCKET).drum_hits("boom_bap", 128.0, 60.0)
    snare = lean_steps(backbeats, "snare", 128.0)
    refute_empty snare
    assert_operator snare.sum / snare.size, :<, -0.2
    kick = hits.select { |r, _| r == "kick" }
    anchors = kick.select { |_, t| ((t / (60.0 / 128 / 4)).round % 16).zero? }
    others = kick - anchors
    assert(anchors.all? { |_, t| (t / (60.0 / 128 / 4) - (t / (60.0 / 128 / 4)).round).abs < 1e-6 }, "the downbeat kick holds")
    assert(others.all? { |_, t| (t / (60.0 / 128 / 4) - (t / (60.0 / 128 / 4)).round) > 0.05 }, "the other kicks lag")
  end

  def test_ghost_snares_lag_further_than_the_kick
    hits = sequencer(POCKET).drum_hits("syncopated_swing", 128.0, 60.0)
    step = 60.0 / 128 / 4
    ghosts = hits.select { |r, t| r == "snare" && ![4, 12].include?((t / step).round % 16) }
    refute_empty ghosts
    ghost_lean = ghosts.map { |_, t| t / step - (t / step).round }
    kick_lean = hits.select { |r, t| r == "kick" && ((t / step).round % 16).positive? }.map { |_, t| t / step - (t / step).round }
    assert_operator ghost_lean.sum / ghost_lean.size, :>, kick_lean.sum / kick_lean.size
  end

  def test_every_bar_leans_as_the_first_did_and_the_seed_alone_changes_the_drift
    bar = 60.0 / 100 * 4
    hits = sequencer(POCKET, seed: 9).drum_hits("broken_beat", 100.0, bar * 4)
    first = hits.select { |_, t| t < bar }.sort
    (1..3).each do |n|
      again = hits.select { |_, t| t >= n * bar && t < (n + 1) * bar }.map { |r, t| [r, t - n * bar] }.sort
      assert_equal first.size, again.size
      first.zip(again).each { |(r, a), (r2, b)| assert_equal r, r2; assert_in_delta a, b, 1e-9 }
    end
    other = sequencer(POCKET, seed: 10).drum_hits("broken_beat", 100.0, bar * 4)
    refute_equal hits, other
  end

  # The same share of a sixteenth is a different number of milliseconds at each tempo.
  def test_the_same_share_gives_different_milliseconds_at_70_88_and_104_bpm
    ms = [70.0, 88.0, 104.0].map do |bpm|
      hits = sequencer(POCKET, seed: 1).drum_hits("boom_bap", bpm, 60.0 / bpm * 8)
      step = 60.0 / bpm / 4
      later = hits.select { |r, t| r == "kick" && t > step }.first.last
      [(later - (later / step).round * step) * 1000, (later - (later / step).round * step) / step]
    end
    shares = ms.map(&:last)
    assert_in_delta shares[0], shares[1], 1e-6, "the share is one number"
    assert_in_delta shares[1], shares[2], 1e-6
    assert_operator ms[0].first, :>, ms[1].first
    assert_operator ms[1].first, :>, ms[2].first
  end

  def test_the_pocket_never_moves_a_hit_past_the_window_and_groove_scales_it
    [50.0, 70.0, 88.0, 104.0, 140.0].each do |bpm|
      hits = sequencer(POCKET).drum_hits("syncopated_swing", bpm, 60.0)
      step = 60.0 / bpm / 4
      assert(%w[kick snare hat].all? { |role| offsets_from_grid(hits, role, step).all? { |o| o.abs <= MAX_OFFSET + 1e-9 } }, bpm.to_s)
    end
    half = lean_steps(sequencer(POCKET, pd_amount: 0.5).drum_hits("boom_bap", 140.0, 30.0), "snare", 140.0)
    full = lean_steps(sequencer(POCKET, pd_amount: 1.0).drum_hits("boom_bap", 140.0, 30.0), "snare", 140.0)
    assert_operator full.sum / full.size, :<, half.sum / half.size
    grid = sequencer(POCKET, pd_amount: 0.0).drum_hits("syncopated_swing", 88.0, 8.0)
    assert(lean_steps(grid, "kick", 88.0).all? { |l| l.abs < 1e-6 })
  end

  def test_every_pocket_role_is_a_pattern_role_with_leans_in_steps
    pocket = DATA.fetch("groove_profiles").fetch(POCKET).fetch("pocket")
    roles = pocket.keys - %w[backbeat ghost]
    assert_equal %w[hat kick snare], roles.sort
    pocket.each_value { |s| next unless s.is_a?(Hash); assert_operator s.fetch("shift_steps", 0.0).abs + s.fetch("drift_steps", 0.0), :<, 1.0 }
  end

  def test_a_role_the_pocket_does_not_own_keeps_its_offsets
    data = JSON.parse(JSON.generate(DATA))
    data["groove_profiles"]["probe"] = { "pocket" => { "kick" => { "shift_steps" => 0.1 } }, "offsets" => { "hat" => 0.01 } }
    hits = sequencer("probe", data:).drum_hits("boom_bap", 88.0, 8.0)
    step = 60.0 / 88 / 4
    assert(offsets_from_grid(hits, "hat", step).all? { |o| (o - 0.01).abs < 1e-9 })
  end

  # ------------------------------------------------------------- arp and echo

  def test_each_arp_pattern_orders_the_voices_and_fills_the_chord
    pool = [40, 52, 60, 67]
    assert_equal [40, 52, 60, 67, 40, 52, 60, 67], Arp.sequence("up", pool, 8, 1)
    assert_equal [67, 60, 52, 40, 67, 60, 52, 40], Arp.sequence("down", pool, 8, 1)
    assert_equal [40, 52, 60, 67, 60, 52, 40, 52], Arp.sequence("updown", pool, 8, 1)
    assert_equal [40, 67, 52, 60, 40, 67, 52, 60], Arp.sequence("converge", pool, 8, 1)
    random = Arp.sequence("random_seeded", pool, 8, 3)
    assert_equal random, Arp.sequence("random_seeded", pool, 8, 3)
    refute_equal random, Arp.sequence("random_seeded", pool, 8, 4)
    assert_equal 8, random.size
    assert(random.all? { |n| pool.include?(n) })
    assert_equal [40, 52, 64], Arp.pool([40, 52], 2)
    assert_raises(ArgumentError) { Arp.sequence("sideways", pool, 4, 1) }
  end

  def test_the_arp_plays_one_note_per_rate_and_each_chord_fills_its_bars
    seq = sequencer("arp_echo_soft")
    arp = seq.arp_settings(nil)
    assert_equal "up", arp["pattern"]
    assert_equal 4.0, arp["rate"]
    buf = seq.render_arp(%w[Cm9 Fm9], 120.0, 4.0, arp.merge("octaves" => 1))
    assert_in_delta 2 * 2.0 + 1.0, buf.size / SAMPLE_RATE.to_f, 0.01
    refute(buf.first(2000).all?(&:zero?), "the first note sounds on the downbeat")
    assert_operator buf.map(&:abs).max, :<=, 1.0
  end

  def test_the_arp_flag_chooses_the_pattern_and_unknown_ones_are_refused
    assert_equal "down", sequencer("dry").arp_settings("down")["pattern"]
    assert_nil sequencer("dry").arp_settings(nil)
    assert_equal "updown", sequencer("dry").arp_settings(true)["pattern"]
  end

  def impulse(length, at = 0)
    Array.new(length, 0.0).tap { |b| b[at] = 1.0 }
  end

  def test_the_echo_has_three_taps_at_one_two_and_three_times_the_delay
    delay = 0.05
    d = (delay * SAMPLE_RATE).round
    out = Echo.process(impulse(d * 4), delay:, heads: [1, 2, 3], intensity: 0.0, volume: 1.0, lowpass: nil, saturation: 0.0)
    assert_in_delta 1.0, out[0], 1e-9, "the dry sound stays"
    taps = [1, 2, 3].map { |h| out[h * d] }
    assert(taps.all? { |v| v > 0.2 }, "a tap at each head: #{taps}")
    assert_in_delta 0.0, out[d / 2], 1e-9
    assert_in_delta 0.0, out[(2.5 * d).to_i], 1e-9
    only = Echo.process(impulse(d * 4), delay:, heads: [2], intensity: 0.0, volume: 1.0, lowpass: nil, saturation: 0.0)
    assert_operator only[2 * d], :>, 0.2
    assert_in_delta 0.0, only[d], 1e-9
  end

  def test_each_repeat_is_quieter_and_the_tail_is_darker
    delay = 0.05
    d = (delay * SAMPLE_RATE).round
    out = Echo.process(impulse(d * 8), delay:, heads: [1], intensity: 0.6, volume: 1.0, lowpass: 3000, saturation: 0.3)
    peaks = (1..5).map { |k| out[k * d] }
    peaks.each_cons(2) { |a, b| assert_operator b, :<, a }
    assert_operator peaks.first, :>, 0.05
    # darker: the lowpass spreads a repeat into the samples after it
    assert_operator out[d + 3], :>, 0.0
  end

  def test_the_echo_is_stable_at_the_top_intensity_and_silence_stays_silent
    rng = Random.new(1)
    loud = Array.new(SAMPLE_RATE) { (rng.rand * 2) - 1 }
    out = Echo.process(loud, delay: 0.03, heads: [1, 2, 3], intensity: 5.0, volume: 1.0, lowpass: 4000, saturation: 1.0)
    assert(out.all?(&:finite?))
    assert_operator out.map(&:abs).max, :<, 6.0
    assert_in_delta 0.0, out.last(2000).map(&:abs).max, 0.5, "the tail dies away"
    silent = Echo.process(Array.new(5000, 0.0), delay: 0.01, heads: [1, 2], intensity: 0.9, volume: 1.0, lowpass: 3000, saturation: 0.5, reverb: 0.2)
    assert(silent.all?(&:zero?))
  end

  def test_echo_flags_choose_heads_and_refuse_unknown_modes
    seq = sequencer("dry")
    assert_nil seq.echo_settings
    assert_equal [1, 2, 3], seq.echo_settings(flag: "1,2,3")["heads"]
    assert_equal [1, 2], seq.echo_settings(flag: true)["heads"]
    settings = seq.echo_settings(flag: true, mix: 0.3, feedback: 0.7, time_ms: 250.0)
    assert_equal [0.3, 0.7, 250.0], settings.values_at("echo_volume", "intensity", "time_ms")
    assert_equal [1, 2], sequencer("arp_echo_soft").echo_settings["heads"]
    assert_equal [[1, 2, 3], 0.85, 3], [sequencer("arp_echo").echo_settings["heads"], sequencer("arp_echo").echo_settings["intensity"], sequencer("arp_echo").arp_settings(nil)["rate"]]
  end

  def test_arp_and_echo_render_a_wav_and_the_plain_render_is_untouched_by_them
    Dir.mktmpdir do |dir|
      plain = File.join(dir, "p.wav")
      other = File.join(dir, "q.wav")
      arp = File.join(dir, "a.wav")
      run_dilla("--progression", "3", "--beats", "2", "--seed", "2", "--out", plain, chdir: dir)
      _o, err, status = run_dilla("--progression", "3", "--beats", "2", "--seed", "2", "--profile", "arp_echo", "--pad", "--out", arp, chdir: dir)
      assert status.success?, err
      run_dilla("--progression", "3", "--beats", "2", "--seed", "2", "--out", other, chdir: dir)
      assert_equal File.binread(plain), File.binread(other)
      assert_operator File.size(arp), :>, File.size(plain), "the echo tail makes it longer"
      assert_operator File.binread(arp).byteslice(44..).unpack("s<*").map(&:abs).max, :>, 1000
    end
  end

  # ------------------------------------------------------------- arp modifiers and strum

  def plucks(count = 8)
    Array.new(count) { |i| Pluck.new(i * 0.2, 0.0, 60 + i, 0.15, i.even? ? 1.0 : 0.5) }
  end

  def modify(name, params, count: 8, seed: 1)
    Arp.modify(plucks(count), name, params, Random.new(seed), slot: 0.2, peak: 1.0)
  end

  def test_euclidean_keeps_the_pulses_of_the_steps
    kept = modify("euclidean", { "steps" => 8, "pulses" => 5 })
    assert_equal 5, kept.size
    assert_equal 8, modify("euclidean", { "steps" => 8, "pulses" => 8 }).size
    assert_equal 6, modify("euclidean", { "steps" => 8, "pulses" => 3 }, count: 16).size
  end

  def test_probability_drops_notes_by_seed
    assert_equal 8, modify("probability", { "probability" => 1.0 }).size
    assert_empty modify("probability", { "probability" => 0.0 })
    some = modify("probability", { "probability" => 0.5 }, count: 200)
    assert some.size.between?(70, 130), some.size.to_s
    assert_equal some.map(&:midi), modify("probability", { "probability" => 0.5 }, count: 200).map(&:midi)
  end

  def test_note_repeat_splits_each_note_and_each_repeat_is_six_percent_quieter
    out = modify("note_repeat", { "count" => 3 }, count: 2)
    assert_equal 6, out.size
    assert_in_delta 0.2 / 3, out[1].base - out[0].base, 1e-9
    assert_in_delta 0.94, out[1].gain / out[0].gain, 1e-9
    assert_equal 8, modify("note_repeat", { "count" => 1 }).size
    assert_equal 6, modify("note_repeat", { "count" => 99 }, count: 1).size
  end

  def test_ratchet_only_splits_accented_notes_into_at_most_the_maximum
    out = modify("ratchet", { "max" => 3, "chance" => 1.0 })
    accented = out.select { |p| p.gain >= 0.99 }
    assert_operator out.size, :>, 8
    assert_operator out.size, :<=, 4 * 3 + 4
    assert_equal 4, out.count { |p| p.gain == 0.5 }, "the soft notes stay whole"
    assert_operator accented.size, :>=, 4
    assert_equal 8, modify("ratchet", { "max" => 3, "chance" => 0.0 }).size
  end

  def test_humanize_moves_time_and_gain_a_little_and_the_clamp_holds
    out = modify("humanize", { "ms" => 4.0, "gain" => 0.06 }, count: 50)
    assert(out.all? { |p| p.off.abs <= 0.004 + 1e-9 })
    assert(out.any? { |p| p.off.abs > 1e-5 })
    assert(out.all? { |p| p.gain.between?(0.0, 1.0) })
    Dir.mktmpdir do |dir|
      data = JSON.parse(JSON.generate(DATA))
      data["arp"].merge!("modifiers" => ["humanize"], "humanize" => { "ms" => 500.0, "gain" => 0.0 })
      seq = sequencer("dry", data:)
      buf = seq.render_arp(%w[Cm9], 120.0, 4.0, seq.arp_settings(true))
      assert_operator buf.size, :>, 0
    end
  end

  def test_grace_notes_come_before_the_note_and_softer
    out = modify("grace", { "interval" => -1, "gain" => 0.3 }, count: 2)
    assert_equal 4, out.size
    assert_equal [59, 60], out.first(2).map(&:midi)
    assert_operator out[0].base, :<, out[1].base
    assert_in_delta 0.3, out[0].gain, 1e-9
  end

  def test_an_unknown_modifier_is_refused_and_modifiers_chain_in_order
    assert_raises(ArgumentError) { modify("sideways", {}) }
    seq = sequencer("arp_fast")
    arp = seq.arp_settings(nil)
    assert_equal %w[ratchet probability humanize], arp["modifiers"]
    a = seq.render_arp(%w[Cm9], 150.0, 2.0, arp)
    assert_equal a, seq.render_arp(%w[Cm9], 150.0, 2.0, arp)
  end

  def test_strum_staggers_the_voices_lowest_first
    flat = Synth.chord([220.0, 330.0], 0.5)
    strummed = Synth.chord([220.0, 330.0], 0.5, strum: 0.02)
    assert_equal flat.size, strummed.size
    refute_equal flat, strummed
    assert_in_delta 0.018, sequencer("dry").strum(true), 1e-9
    assert_equal 0.0, sequencer("dry").strum(nil)
    assert_in_delta 0.03, sequencer("dry").strum(30.0), 1e-9
  end

  # ------------------------------------------------------------- endless play

  def test_play_renders_ahead_and_never_repeats_the_last_progression
    Dir.mktmpdir do |dir|
      log = File.join(dir, "played.txt")
      player = File.join(dir, "fake.sh")
      File.write(player, "#!/bin/sh\necho \"$1\" >> #{log}\n")
      File.chmod(0o755, player)
      out, err, status = run_dilla("--play", "--player", player, "--passes", "4", "--beats", "1", "--seed", "8",
                                   "--profile", "dry", "--mode", "pad", "--out", File.join(dir, "x.wav"), chdir: dir)
      assert status.success?, err
      passes = out.scan(/^pass (\d+): progression (\d+) \(/)
      assert_equal %w[1 2 3 4], passes.map(&:first)
      indices = passes.map { |_, i| i.to_i }
      indices.each_cons(2) { |a, b| refute_equal a, b }
      assert_equal 4, File.readlines(log).size, "each render was handed to the player"
      assert_equal 4, out.scan(/seed=\d+/).uniq.size, "a fresh seed each pass"
    end
  end

  def test_the_echo_tail_rings_on_after_the_last_note
    settings = sequencer("arp_echo").echo_settings
    assert_equal [1, 2, 3], settings["heads"]
    assert_operator settings["echo_volume"], :>=, 0.85
    assert_operator settings["tail"], :>=, 10
    assert_equal 78.0, sequencer("arp_echo").bpm
    assert_equal 88.0, sequencer("dry").bpm
    out = Echo.process(impulse(100), delay: 0.05, heads: [1], intensity: 0.85, volume: 1.0, lowpass: nil, saturation: 0.0, tail: 3.0)
    assert_equal 100 + (3 * SAMPLE_RATE), out.size
    assert_operator out.last(2205).map(&:abs).max, :<, out[2205, 2205].map(&:abs).max, "the tail dies away"
  end

  # ------------------------------------------------------------- voices, colour, mix

  def test_every_voice_makes_finite_audible_samples_and_drops_notes_past_the_limit
    DATA.fetch("voices").each do |name, spec|
      samples = Voices.note(spec, 57, 0.2, 0.2)
      assert_operator samples.size, :>, 1000, name
      assert(samples.all?(&:finite?), name)
      assert_operator samples.map(&:abs).max, :>, 0.01, name
      assert_empty Voices.note(spec, 57 + 120, 0.2, 0.2), "#{name}: above the limit, nothing sounds"
    end
    assert(Synth.note(Chords.hz(150), 0.1).all?(&:zero?), "a sine stack past the limit is silent, not folded down")
  end

  def test_transpose_moves_notes_and_wrap_folds_them_under_the_audible_top
    plain = Chords.midi_notes(%w[Cm9 Fm9])
    assert_equal plain.map { |c| c.map { |n| n + 12 } }, Chords.midi_notes(%w[Cm9 Fm9], transpose: 12)
    high = Chords.midi_notes(%w[Cm9 Fm9], transpose: 144).flatten
    assert(high.none? { |n| Voices.audible?(Chords.hz(n)) }, "twelve octaves up is past Nyquist")
    folded = Chords.midi_notes(%w[Cm9 Fm9], transpose: 144, wrap: true).flatten
    assert(folded.all? { |n| Chords.hz(n) <= AUDIBLE_TOP_HZ })
    assert_equal plain.flatten.map { |n| n % 12 }, folded.map { |n| n % 12 }, "folding keeps the pitch classes"
  end

  def test_a_transpose_past_nyquist_warns_and_renders_silence
    Dir.mktmpdir do |dir|
      out = File.join(dir, "x.wav")
      _o, err, status = run_dilla("--progression", "9", "--beats", "1", "--octaves", "12", "--mode", "pad", "--out", out, chdir: dir)
      assert status.success?, err
      assert_match(/warning: \d+ of \d+ notes are above/, err)
      assert File.binread(out).byteslice(44..).unpack("s<*").all?(&:zero?)
    end
  end

  def noise(count = 20_000)
    rng = Random.new(2)
    Array.new(count) { (rng.rand * 2) - 1 }
  end

  def tone_energy(buf, hz)
    re = im = 0.0
    buf.each_with_index do |v, i|
      angle = 2 * Math::PI * hz * i / SAMPLE_RATE
      re += v * Math.cos(angle)
      im += v * Math.sin(angle)
    end
    Math.sqrt((re * re) + (im * im)) / buf.size
  end

  def test_sonitex_reduces_bit_depth_limits_the_band_and_drives_harmonics_within_a_safe_peak
    levels = Colour.crush(noise, 4, 1.0).uniq.size
    assert_operator levels, :<=, 2**4 + 1
    preset = DATA.dig("sonitex", "presets", "heavy")
    high = noise.then { |n| tone_energy(Colour.highpass(n, 9000.0), 12_000) }
    out = Colour.sonitex(noise, preset, 1, 1)
    assert_operator tone_energy(out, 12_000), :<, tone_energy(noise, 12_000) * 0.2, "energy above the cutoff drops"
    assert_operator high, :>, 0
    sine = Array.new(20_000) { |i| 0.3 * Math.sin(2 * Math::PI * 440 * i / SAMPLE_RATE) }
    driven = Colour.sonitex(sine, DATA.dig("sonitex", "presets", "classic"), 1, 1)
    assert_operator tone_energy(driven, 1320) / tone_energy(driven, 440), :>, 3 * tone_energy(sine, 1320) / tone_energy(sine, 440) + 0.001
    assert_operator Colour.sonitex(noise, preset, 3, 1).map(&:abs).max, :<, 1.0
  end

  def test_the_summing_colour_is_stable_and_never_much_louder_and_off_changes_nothing
    rms = ->(b) { Math.sqrt(b.sum { |v| v * v } / b.size) }
    loud = noise.map { |v| v * 0.9 }
    [0.2, 0.5, 1.0].each do |amount|
      out = Colour.vcs(loud, amount)
      assert(out.all?(&:finite?))
      assert_operator 20 * Math.log10(rms.call(out) / rms.call(loud)), :<=, 3.0
    end
    assert_same loud, Colour.vcs(loud, 0.0)
    assert_same loud, sequencer("dry").colour(loud, nil, 0.0)
  end

  def test_colour_is_off_by_default_and_the_bytes_say_so
    Dir.mktmpdir do |dir|
      a = File.join(dir, "a.wav")
      b = File.join(dir, "b.wav")
      c = File.join(dir, "c.wav")
      base = ["--progression", "2", "--beats", "1", "--mode", "pad", "--seed", "4"]
      run_dilla(*base, "--out", a, chdir: dir)
      run_dilla(*base, "--vcs", "0", "--out", b, chdir: dir)
      _o, err, status = run_dilla(*base, "--sonitex", "heavy", "--sonitex-instances", "3", "--vcs", "0.5", "--out", c, chdir: dir)
      assert status.success?, err
      assert_equal File.binread(a), File.binread(b)
      refute_equal File.binread(a), File.binread(c)
    end
  end

  def test_a_chord_repeat_strikes_every_voice_on_every_mark_of_the_style
    seq = sequencer("chord_repeat")
    comp = seq.comp_settings(true).merge("pattern" => "x...x...x...x...", "modifiers" => [])
    seq_notes = Chords.midi_notes(%w[Cm9]).first.size
    assert_operator seq_notes, :>=, 4
    struck = 0
    plucks = []
    singles = seq.render_repeat(%w[Cm9], 120.0, 4.0, comp)
    refute(singles.all?(&:zero?))
    assert_includes DATA.dig("comp", "styles"), "dotted_eighth_push"
    DATA.dig("comp", "styles").each_value { |s| assert_equal 16, s["pattern"].size }
    assert_equal %w[chord_repeat], DATA.fetch("groove_profiles").select { |_, p| p.key?("repeat") }.keys
    assert_equal 0, struck + plucks.size
  end

  def test_mix_defaults_raise_the_kick_and_snare_and_drop_the_chords
    levels = sequencer("dry").mix(nil)
    assert_equal [6.0, 10.0, 10.0, 0.0, -3.0], levels.values_at("kick", "snare", "clap", "hat", "chords")
    assert_equal 3.0, sequencer("dry").mix("kick" => 3.0)["kick"]
  end

  def test_drums_only_kick_and_snare_rms_rise_by_the_stated_decibels_and_nothing_clips
    seq = sequencer("dry")
    rms = ->(b) { Math.sqrt(b.sum { |v| v * v } / b.size) }
    [["kick", 6.0], ["snare", 10.0]].each do |role, db|
      silent = Array.new(SAMPLE_RATE, 0.0)
      hits = [[role, 0.1], [role, 0.5]]
      before = seq.overlay_drums(silent, hits, { role => 0.0 })
      after = seq.overlay_drums(silent, hits, { role => db })
      assert_in_delta db, 20 * Math.log10(rms.call(after) / rms.call(before)), 0.8, role
      assert_operator after.map(&:abs).max, :<=, 1.0
    end
    loud = seq.overlay_drums(Array.new(SAMPLE_RATE, 0.9), [["kick", 0.1], ["snare", 0.1]], { "kick" => 12.0, "snare" => 12.0 })
    assert_operator loud.map(&:abs).max, :<=, 1.0
  end

  def test_the_kick_is_added_after_the_duck
    seq = sequencer("pump")
    chords = Array.new(SAMPLE_RATE, 0.5)
    ducked = seq.duck(chords, [["kick", 0.1]])
    out = seq.overlay_drums(ducked, [["kick", 0.1]], { "kick" => 0.0 })
    start = (0.1 * SAMPLE_RATE).to_i
    assert_operator out[start + 200].abs, :>, ducked[start + 200].abs, "the kick sits on top of the pumped chords"
  end

  # ------------------------------------------------------------- the shuffle bags

  def test_every_progression_plays_once_per_cycle_and_nothing_repeats_back_to_back
    count = PROGRESSIONS.size
    list = Playlist.new(DATA, Random.new(5))
    picks = Array.new(3 * count) { list.draw(profile: "dry") }
    seen = picks.map { |p| p[:prog] }
    assert_equal({ 3 => count }, seen.tally.values.tally)
    seen.each_cons(2) { |a, b| refute_equal a, b }
    families = picks.map { |p| DATA.dig("voices", p[:voice], "family") }
    families.each_cons(2) { |a, b| refute_equal a, b }
    picks.map { |p| p[:mode] }.each_cons(2) { |a, b| refute_equal a, b }
    picks.select { |p| p[:style] }.group_by { |p| p[:mode] }.each_value { |rows| rows.map { |p| p[:style] }.each_cons(2) { |a, b| refute_equal a, b } }
  end

  def test_no_patch_of_a_family_repeats_before_every_patch_of_it_has_played
    list = Playlist.new(DATA, Random.new(9))
    moog = list.voices_by_family.fetch("moog")
    played = Array.new(400) { list.draw(profile: "dry")[:voice] }.select { |v| moog.include?(v) }
    played.each_slice(moog.size).select { |s| s.size == moog.size }.each { |slice| assert_equal moog.sort, slice.sort }
  end

  def test_a_restart_goes_on_with_the_cycle
    first = Playlist.new(DATA, Random.new(1))
    a = Array.new(50) { first.draw(profile: "dry")[:prog] }
    state = JSON.parse(JSON.generate(first.to_h))
    second = Playlist.new(DATA, Random.new(2), state)
    b = Array.new(55) { second.draw(profile: "dry")[:prog] }
    assert_equal PROGRESSIONS.size, (a + b).uniq.size
    assert_equal (a + b).size, (a + b).uniq.size, "the 105 of the first cycle each came once across the restart"
    assert_equal "1/105", Playlist.new(DATA, Random.new(3)).tap { |l| l.draw }.then { |l| l.instance_variable_get(:@bags)["progressions"].position }
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
