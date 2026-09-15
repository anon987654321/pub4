# frozen_string_literal: true

require_relative "dilla_helper"
require "tmpdir"

# Operator directives, pinned so an edit cannot quietly undo one.
#
# Every test here is a thing the operator asked of dilla, named with the date
# and the words it was asked in. Each asserts the rule the code declares for it,
# and each was seen to fail with that rule broken before it was committed. A
# directive the tree does not honour yet has no test here: a test written to
# the tree's current shape would pin the violation instead of the request.
#
#   F3 2026-09-09 "drum-wise can we alternate between hiphop drums and techno drums?"
#   F5 2026-09-09 "for the techno drum loops, you can cut out the distorted tunnel effect"
#   D1 2026-09-08 "extrapolate leads based on the scales of the current progressions"
#   D5 2026-09-08 "the leads sound HORRIBLE!!" (octave-only copies)
#   F1 2026-09-08 "we need a completely new pattern ... study the book 'dillatime'"
#   A4 2026-09-08 "drop all dependence on audio samples; synthesize everything yourself"
#   K3 standing   samples are slowed short ideas, never sped up
#   G10 standing  never render over a take that matters
class TestDillaDirectives < Minitest::Test
  # F3, 2026-09-09: "drum-wise can we alternate between hiphop drums and techno
  # drums?" Alternation is by period, not by coin: techno on every second slot of
  # the nineteen, starting with the second.
  def test_the_catalogue_alternates_hiphop_and_techno_slot_by_slot
    with_env("DEMO_TECHNO_EVERY" => nil, "DEMO_TECHNO_SHARE" => nil, "TECHNO_HARMONY" => nil) do
      order = demo_curated_order
      techno = order.each_with_index.map { |slug, index| demo_techno_slot?(index, slug.to_s) }

      assert_equal 19, order.size
      assert_equal Array.new(19) { |index| index.odd? }, techno
    end
  end

  # F5, 2026-09-09: "for the techno drum loops, you can cut out the distorted
  # tunnel effect". The tunnel is the echo, flanger and phaser on the metal and
  # chirp voices; HATE_TUNNEL=1 is the one way back to it.
  def test_the_techno_metal_and_chirp_voices_carry_no_tunnel
    plain = hate_techno_chains("HATE_TUNNEL" => nil)
    tunnel = hate_techno_chains("HATE_TUNNEL" => "1")

    %w[metal bleep].each do |voice|
      refute_match TUNNEL, plain.fetch(voice), "#{voice} still runs through the tunnel"
      assert_match TUNNEL, tunnel.fetch(voice), "HATE_TUNNEL=1 no longer restores the #{voice} tails"
    end
  end

  # F5 again: the ringtone chain runs over every demo slot, techno ones
  # included, so it drops the same three stages.
  def test_the_ringtone_demo_chain_carries_no_tunnel
    refute_match TUNNEL, ringtone_chain("HATE_TUNNEL" => nil)
    assert_match TUNNEL, ringtone_chain("HATE_TUNNEL" => "1")
  end

  # D1, 2026-09-08: "on top of the pads, can you extrapolate leads based on the
  # scales of the current progressions?" and 2026-09-13 "leads must be in scale
  # with chords". ImprovisedLine.lead declares the placement: the downbeat is a
  # guide tone of the chord, the passing tone is in the chord's scale, the line
  # lands on a guide tone of the next chord, and the one chromatic note is the
  # approach, a semitone from that landing, off the beat.
  def test_improvised_lead_notes_follow_the_chords_they_sit_on
    placed = Hash.new(0)
    with_env("LEAD_DENSITY" => "1.0") do
      catalogue_chord_pairs.each do |chord, following|
        20.times do |seed|
          notes = ImprovisedLine.lead(chord, following, 0.0, 4.0, Random.new(seed))
          notes.each { |note| placed[check_lead_note(note, notes, chord, following)] += 1 }
        end
      end
    end

    %i[downbeat passing approach landing].each { |role| assert_operator placed[role], :>, 0, "no #{role} note was checked" }
  end

  # D5, 2026-09-08: "the leads sound HORRIBLE!!". A copy of the line is an
  # octave of it, never a fifth: a fifth over every note of a lead above a pad
  # is what an unusable lead sounds like.
  # The same complaint, answered in the voices: a lead patch has no saw and a
  # filter that does not ring, since nothing above a pad masks either.
  def test_improvised_lead_patches_have_no_saw_and_a_quiet_filter
    IMPROVISED_LEAD_PATCHES.each do |name|
      patch = AnalogSynth::PATCHES.fetch(name)
      refute_includes patch.fetch(:waves), :saw, "#{name} plays a saw"
      assert_operator patch.fetch(:resonance), :<=, 0.2, "#{name} rings"
    end
  end

  def test_lead_copies_are_octaves_only
    ImprovisedLine::LEAD_RATIOS.each do |ratio|
      octaves = Math.log2(ratio)
      assert_in_delta octaves.round, octaves, 1e-9, "#{ratio} is not an octave transposition"
    end
  end

  # F1, 2026-09-08: "we need a completely new pattern the current one doesnt
  # sound like hiphop ... study the book 'dillatime'". The dillatime preset
  # declares eleven hits, a snare with no clap doubled onto it, and hats that
  # leave the two backbeat steps open.
  def test_the_dillatime_grid_is_sparse_and_leaves_the_backbeat_open
    grid = DillaLofiMachine::DRUM_PRESETS.fetch(:dillatime)
    hits = %i[kicks snares hats ghosts claps perc].sum { |role| grid.fetch(role).size }

    assert_operator hits, :<=, 12
    assert_empty grid.fetch(:claps) & grid.fetch(:snares), "a clap doubles the snare"
    assert_empty grid.fetch(:hats) & [4, 12], "a hat closes the space the snare arrives into"
  end

  # A4, 2026-09-08: "drop all dependence on audio samples; synthesize everything
  # yourself from scratch". No draw the engine makes per render names a drum
  # loop or a recorded kit: not the kit pick, not the stream rotation, not a
  # role looking for a one-shot. Fifty seeds, because the kit pick once rolled
  # for a sample pack on most renders.
  # Nor does a default: the table every CLI run applies and the album mode
  # name no sample pack, so a kit is only ever an operator's EXTERNAL_KIT.
  def test_no_default_names_a_recorded_kit
    refute DILLA_BEST_DEFAULTS.key?("EXTERNAL_KIT"), "DILLA_BEST_DEFAULTS names a sample pack"
    RENDER_MODE_DEFAULTS.each { |mode, table| refute table.key?("EXTERNAL_KIT"), "RENDER_MODE=#{mode} names a sample pack" }
  end

  def test_no_draw_reaches_for_recorded_drums
    define_singleton_method(:ensure_external_assets_lazy!) { true }
    with_env("EXTERNAL_KIT" => nil, "DRUM_LOOP" => nil, "RENDER_SEED" => nil) do
      assert_nil drum_loop_source

      50.times do |seed|
        ENV["RENDER_SEED"] = seed.to_s
        pick_render_seed!
        pick_external_drum_kit!
        stream_rotate_drums!(seed)

        assert_nil ENV["EXTERNAL_KIT"], "seed #{seed} set EXTERNAL_KIT"
        assert_nil @current_external_kit, "seed #{seed} picked a recorded kit"
        DRUM_SAMPLE_SUBDIR.each_key do |name|
          refute drum_sample_path(name).start_with?(EXTERNAL_DRUM_KIT_CACHE), "seed #{seed} reached the sample pack for #{name}"
        end
      end
    end
  end

  # K3, standing: samples are slowed short ideas, never sped up. The global
  # tempo trim pulls the record down, and the loop is slowed the way a sampler
  # slows it, pitch falling with speed, rather than stretched with pitch held.
  def test_samples_are_slowed_by_varispeed_never_sped_up
    with_env("BPM_SCALE" => nil, "TRACK" => nil, "SAMPLE_LOOP_VARISPEED" => nil, "SAMPLE_LOOP_SEMITONES" => nil) do
      assert_operator BPM_SCALE_DEFAULT.to_f, :<=, 1.0
      assert_operator bpm_scale, :<=, 1.0

      filter = build_sample_loop_filter(0, 8.0, 90.0, 90.0 * bpm_scale)
      assert_match(/asetrate=/, filter)
      refute_match(/atempo=/, filter)
    end
  end

  # G10, standing: never render over a take that matters. render_dilla sets the
  # old take aside as <dest>.prev and puts it back when the new one does not
  # land, whether the render dies before writing or leaves a truncated stub.
  def test_a_failed_render_restores_the_previous_take
    Dir.mktmpdir do |dir|
      dest = File.join(dir, "take.mp3")
      take = Random.new(7).bytes(80_000)
      define_singleton_method(:ensure_drum_kit!) { nil }

      [nil, "stub"].each do |wreckage|
        File.binwrite(dest, take)
        define_singleton_method(:dilla_resolve_config) do
          File.binwrite(dest, wreckage) if wreckage
          raise RenderDied
        end

        with_env("DILLA_OVERWRITE" => "1", "SELF_SAMPLE" => "0") do
          assert_raises(RenderDied) { render_dilla(dest, 2) }
        end

        assert_equal take, File.binread(dest), "the previous take is gone after a render that left #{wreckage.inspect}"
        refute File.exist?("#{dest}.prev"), "the set-aside copy was left behind"
      end
    end
  end

  private

  RenderDied = Class.new(StandardError)
  ChainsSeen = Class.new(StandardError)
  TUNNEL = /\b(?:aecho|flanger|aphaser)=/

  # render_hate_techno writes each voice with one ffmpeg call. The call is
  # recorded instead of run, and the render stops once the chirps are written,
  # before anything mixes.
  def hate_techno_chains(pairs)
    chains = {}
    define_singleton_method(:require_tools!) { |*| nil }
    define_singleton_method(:sh!) do |*argv|
      voice = File.basename(argv.last.to_s, ".wav")
      at = argv.index("-af") || argv.index("-filter_complex")
      chains[voice] = argv[at + 1].to_s if at
      raise ChainsSeen if voice == "bleep"
    end
    with_env(pairs.merge("TECHNO_HARMONY" => "0", "HATE_MELODY" => nil, "HATE_TONAL" => nil)) do
      assert_raises(ChainsSeen) { render_hate_techno(File.join(Dir.tmpdir, "never_written.mp3")) }
    end
    chains
  end

  def ringtone_chain(pairs)
    filters = []
    define_singleton_method(:album_loudness) { |_| { i: 0.0 } }
    # The chain runs through ToolRun, so the stub goes there, and the real
    # function comes back after: module_function keeps it on the singleton.
    original = ToolRun.singleton_class.instance_method(:system)
    ToolRun.define_singleton_method(:system) do |*argv, **|
      filters << argv[argv.index("-af") + 1]
      File.binwrite(argv.last, "fx")
      true
    end
    Dir.mktmpdir do |dir|
      part = File.join(dir, "part.wav")
      File.binwrite(part, "part")
      with_env(pairs.merge("DEMO_FX" => "ringtone")) { demo_ringtone_fx!(part) }
    end
    filters.first.to_s
  ensure
    ToolRun.singleton_class.define_method(:system, original) if original
  end

  # Every chord in the catalogue beside the chord that follows it, the verified
  # recordings and the improvisations both.
  def catalogue_chord_pairs
    verified = VERIFIED_PROGRESSION_SLOTS.filter_map { |name| curated_progression_pads(name) }
    progressions = verified + DillaImprovisation.progression_chords.values
    progressions.flat_map do |chords|
      voiced = chords.map { |chord| Array(chord[:hz]).map(&:to_f).select(&:positive?) }.reject(&:empty?)
      voiced.each_with_index.map { |chord, index| [chord, voiced[(index + 1) % voiced.size]] }
    end
  end

  def check_lead_note(note, notes, chord, following)
    midi = ImprovisedLine.hz_to_midi(note[:hz]).round
    root, scale = ImprovisedLine.scale_for(chord)
    next_root, = ImprovisedLine.scale_for(following)
    case (note[:at] / 0.5).round(1)
    when 0.0
      assert_includes ImprovisedLine.guide_tones(chord), (midi - root) % 12, "downbeat #{midi} over #{chord}"
      :downbeat
    when 3.0
      assert_includes scale, (midi - root) % 12, "passing tone #{midi} outside the scale of #{chord}"
      :passing
    when 6.5
      landing = notes.find { |other| (other[:at] / 0.5).round(1) == 7.0 }
      assert_equal 1, (midi - ImprovisedLine.hz_to_midi(landing[:hz]).round).abs, "approach #{midi} is not a semitone off"
      :approach
    when 7.0
      assert_includes ImprovisedLine.guide_tones(following), (midi - next_root) % 12, "landing #{midi} over #{following}"
      :landing
    else
      flunk "a lead note at #{note[:at]}s sits on no position the line declares"
    end
  end
end
