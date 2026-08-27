# frozen_string_literal: true
#
# Style family, BPM, swing and track preset resolution.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.

def load_radio_bergen_learnings
  return @radio_bergen_learnings if defined?(@radio_bergen_learnings)
  base = Marshal.load(Marshal.dump(INLINE_RADIO_BERGEN_LEARNINGS))
  if File.file?(RADIO_BERGEN_SONIC_PATH)
    file_data = YAML.safe_load(File.read(RADIO_BERGEN_SONIC_PATH), permitted_classes: [Symbol], aliases: true)
    base = merge_sonic_profile_hashes(base, file_data) if file_data.is_a?(Hash)
  end
  if File.file?(PROMOTED_PROFILES_PATH)
    promoted = JSON.parse(File.read(PROMOTED_PROFILES_PATH))
    weights = (base["stream_rotation_weights"] || {}).dup
    promoted.each do |track, count|
      next if track.start_with?("_")
      weights[track.to_s] = (weights[track.to_s] || 0) + count.to_i.clamp(1, 8)
    end
    base["stream_rotation_weights"] = weights
  end
  @radio_bergen_learnings = base
rescue StandardError => e
  warn "radio bergen learnings: #{e.message}"
  @radio_bergen_learnings = Marshal.load(Marshal.dump(INLINE_RADIO_BERGEN_LEARNINGS))
end

def merge_sonic_profile_hashes(base, extra)
  return extra if base.nil?
  return base if extra.nil?
  base.merge(extra) do |_k, left, right|
    left.is_a?(Hash) && right.is_a?(Hash) ? merge_sonic_profile_hashes(left, right) : right
  end
end

def load_sonic_profiles
  return @sonic_profiles if defined?(@sonic_profiles) && @sonic_profiles
  merged = INLINE_SONIC_PROFILES.transform_keys(&:to_sym).transform_values(&:dup)
  extras = load_radio_bergen_learnings["sonic_profiles"]
  if extras.is_a?(Hash)
    extras.each do |key, profile|
      sym = key.to_sym
      merged[sym] = merge_sonic_profile_hashes(merged[sym], profile)
    end
  end
  @sonic_profiles = merged.freeze
end

def radio_bergen_stream_enabled?
  ENV.fetch("RADIO_BERGEN", "1") != "0" && ENV["DILLA_STREAMING"] == "1"
end

def pick_radio_bergen_stream_track!
  return unless radio_bergen_stream_enabled?
  weights = load_radio_bergen_learnings["stream_rotation_weights"]
  return unless weights.is_a?(Hash) && weights.any?
  pool = weights.flat_map { |track, count| Array.new(count.to_i.clamp(1, 12), track.to_s) }
  return if pool.empty?
  picked = render_pick(pool, "stream_track_weight")
  ENV["TRACK"] = picked
  defaults = load_radio_bergen_learnings["stream_env_defaults"]
  if defaults.is_a?(Hash)
    defaults.each do |key, value|
      ENV[key] = value.to_s if ENV[key].nil? || ENV[key].empty?
    end
  end
  RadioBergenStudy.apply_engine_track_dossier!(picked)
  picked
end

def sonic_profile_for(track)
  sym = track.to_sym
  key = TRACK_SONIC_MAP.fetch(sym, nil)
  base = key ? load_sonic_profiles[key] : nil
  return base unless DillaLofiMachine.harmony_profile?(sym)
  synth = (base&.dig("synth") || {}).merge(DillaLofiMachine.lofi_sonic_overlay(sym))
  { "synth" => synth, "harmonic" => base&.dig("harmonic") || {} }
end

def style_family(track, feel: nil)
  if (entry = DillaLofiMachine.profile_entry(track))
    return :wonky if entry[:producer] == :wonky
    return :madlib if entry[:producer] == :madlib
    return :dilla
  end
  return :wonky if WONKY_TRACKS.include?(track.to_sym) || feel == :loose_pocket
  return :dilla if DILLA_TRACKS.include?(track.to_sym) ||
                   %i[timeless organic chromatic_planing syncopated_slash_ninth
                      dilla_slight dilla_drunk madlib_dusty wonky_abstract mpc3000 sp303 sp1200].include?(feel)
  return :madlib if track.to_s.include?("madlib")
  :default
end

# A global tempo trim, so "slow the beats down" scales the whole table rather than
# pinning one number.
#
# Every profile carries its own tempo -- 86 on the Wonky transcriptions, 91 on the
# Slum Village ones, 96 on the harder pockets -- and the distances between them are
# the point. BPM=88 would flatten all of them into one tempo and lose what separates
# a Camel from a Players, so the trim multiplies whatever each track already asked
# for and the relationships survive.
#
# The check is USER_PINNED_ENV, not ENV: the defaults tables write ENV["BPM"]
# themselves, so gating on that would mean the trim silently stopped applying the
# moment any style preset ran. An operator who names a tempo still gets it exactly.
BPM_SCALE_DEFAULT = "0.96"

def bpm_scale
  return 1.0 if USER_PINNED_ENV["BPM"].to_s.strip.match?(/\A\d/)

  scale = (ENV["BPM_SCALE"] || BPM_SCALE_DEFAULT).to_f
  scale.positive? ? scale.clamp(0.5, 1.5) : 1.0
end

# The record sets the tempo, not the other way round.
#
# Every chop was being dragged to one render tempo, and because varispeed is on
# (correctly -- see build_sample_loop_filter) tempo and pitch move together. The
# eight ubrukte_samples chops sit at 73.6 to 122.4 BPM natively; against a fixed
# 92 that is ratio 1.25 down to 0.75, which is +3.9 to -4.9 SEMITONES of
# transposition applied purely as a side effect of a number nobody chose per
# track. It flattens what separates the chops and smears the transients of
# exactly the ones that were most distinct -- eight records rendered as one.
#
# Rendering at the chop's own tempo makes the ratio 1.0: no stretch, no
# transposition, and the tempo variety that was in the source material comes
# back for free. Folded into a single octave first, because a detector reports a
# period and a period reads as half or double its true value -- the same trap
# acapella.rb's BPM_RANGE fell into. 70-140 has no hole in it.
#
# BPM= and a sonic preset still win: an operator naming a tempo means it.
SAMPLE_BPM_FLOOR = 70.0
SAMPLE_BPM_CEILING = 140.0

def fold_to_octave(bpm)
  value = bpm.to_f
  return unless value.positive?

  value *= 2.0 while value < SAMPLE_BPM_FLOOR
  value /= 2.0 while value >= SAMPLE_BPM_CEILING
  value
end

def sample_native_bpm(track)
  return unless ENV.fetch("SAMPLE_NATIVE_BPM", "1") != "0"

  entry = sample_loop_entry(track) or return
  return unless File.file?(entry[:path].to_s)

  fold_to_octave(entry[:bpm])
rescue StandardError => e
  dmesg("native bpm unavailable: #{e.class}", unit: "smpl0", parent: "dilla0")
  nil
end

def resolve_bpm(preset, track, sonic)
  env_bpm = ENV["BPM"]&.to_f
  sonic_bpm = sonic&.dig("synth", "bpm")&.to_f

  # USER_PINNED_ENV, not ENV -- the same distinction bpm_scale draws, and for
  # the same reason. The style tables write ENV["BPM"] themselves, so gating on
  # ENV would mean the record's own tempo never won against a default nobody
  # typed. Only a tempo the operator actually named outranks the record.
  pinned = USER_PINNED_ENV["BPM"].to_s.strip.match?(/\A\d/)
  native = (sample_native_bpm(track) unless pinned)

  base = if pinned
           env_bpm
         elsif native
           dmesg(format("tempo from the record: %.1f bpm (no stretch)", native), unit: "smpl0", parent: "dilla0")
           native
         elsif sonic_bpm&.positive?
           sonic_bpm
         elsif env_bpm&.positive?
           env_bpm
         else
           preset.fetch(:bpm, DEFAULT_BPM).to_f
         end
  (base * bpm_scale).round(2)
end

def resolve_swing(preset, sonic, time_offset)
  return 62.5 if ENV["GOLDEN_SWING"] == "1"
  return ENV["SWING"].to_f if ENV["SWING"]
  sonic_swing = sonic&.dig("synth", "swing")&.to_f
  if DillaLofiMachine.harmony_profile?((ENV["TRACK"] || DillaLofiMachine::DEFAULT_PROFILE).to_s.downcase.tr("-", "_").to_sym)
    return preset.fetch(:swing, 54).to_f + time_offset
  end
  base = if sonic_swing && sonic_swing < 1.0
           DillaLofiMachine.mpc_swing_from_sonic_fraction(sonic_swing) + time_offset
         else
           preset.fetch(:swing, 54).to_f + time_offset
         end
  # Back to 66. This was raised to 72 on the strength of a forum assertion that
  # MPC swing "goes to about 70% on 16ths". Better sources disagree and are more
  # specific: the Dilla swing sits around 53-56%, applied to EIGHTH notes, and
  # the off-kilter quality comes from quantise being off entirely and hits
  # nudged by hand rather than from a high swing percentage. A ceiling of 72
  # permits a value no source supports and invites chasing the wrong parameter.
  #
  # What those sources describe instead is varying degrees of swing across
  # different voices, which is SWING_ROLE_SCALE below. That is the
  # near-polyrhythmic quality; one large global swing is not the same thing and
  # does not sound like it.
  base.clamp(50.0, 66.0)
end

def track_preset(track)
  prod = DillaLofiMachine.profile_preset(track)
  return prod if prod
  return TRACK_PRESETS[track] if TRACK_PRESETS.key?(track)
  base = TRACK_PRESETS[:timeless].dup
  base[:progression] = track if CHORD_PROGRESSIONS.key?(track)
  base
end

def curated_progression?(cfg)
  # A documented transcription is curated by definition.
  #
  # This predicate decides whether a progression loops as written or falls to
  # arrange_fugue_progression, which develops it into exposition/development/
  # recapitulation over a pedal. The four entries from dilla_reference.yml were
  # on neither the local nor the DillaLofiMachine list, so asking for
  # slum_village_players_documented rendered a fugue: the log read
  # "TRACK=slum_village_players_documented BPM=91.0 (fugue)" and the chords that
  # played were D/E, Db/E, C/E, Bm/E, Bbm/E -- a chromatic descent over an E
  # pedal, with no Cm9, Fm9, Bb13 or Ebmaj7 anywhere in it.
  #
  # Developing a transcription defeats the point of transcribing it. Every entry
  # in that file is suffixed _documented, which is the marker used here.
  CURATED_PROGRESSIONS.include?(cfg[:progression].to_sym) ||
    DillaLofiMachine::CURATED_PROGRESSIONS.include?(cfg[:progression].to_sym)
end

def enhanced_resolve_config
  track = (ENV["TRACK"] || DillaLofiMachine::DEFAULT_PROFILE).to_s.downcase.tr("-", "_").to_sym
  preset = track_preset(track)
  prog = (ENV["PROGRESSION"] || preset.fetch(:progression, track)).to_s.downcase.tr("-", "_").to_sym
  sonic = sonic_profile_for(track)
  # DRUM_FEEL names the drum PATTERN vocabulary — DRUM_PATTERN_SETS — and it had
  # no way in. The value came only from the track preset, so a set no preset
  # declared could not be reached at all: dilla_canon, wonky_canon and one_drop
  # were written, commented, and selected by nothing. dilla_canon is the one
  # carrying Dilla's own kick anchors (0/3/10), the ghosts and the displaced
  # snares, in an engine named after him.
  #
  # Not to be confused with GROOVE_FEEL, which is the microtiming TICK table in
  # DillaGroove::GROOVE_FEELS (boom_bap/dilla_drag/camel). The two share the word
  # "feel", have disjoint vocabularies, and feed different code paths — setting
  # GROOVE_FEEL=dilla_canon silently gives you dilla_drag timing and whatever
  # patterns the track already had, which reads as the knob working.
  #
  # Default is unchanged, so no existing render moves.
  feel = (ENV["DRUM_FEEL"].to_s.strip.empty? ? nil : ENV["DRUM_FEEL"].downcase.tr("-", "_").to_sym) ||
         preset[:feel] || :default
  family = style_family(track, feel:)
  {
    track:,
    bpm: resolve_bpm(preset, track, sonic),
    progression: prog,
    chord_bars: resolve_chord_bars(preset),
    phrase_bars: preset[:phrase_bars],
    swing: resolve_swing(preset, sonic, time_of_day_swing_offset),
    feel:,
    stereo_pan: preset[:stereo_pan] || false,
    timing: preset[:timing],
    quintuplet: ENV["QUINTUPLET"] ? ENV["QUINTUPLET"] != "0" : (preset[:quintuplet] || false),
    sonic:,
    style_family: family,
    sidechain: ENV["SIDECHAIN"] != "0" && (family == :wonky || preset[:sidechain] || sonic&.dig("synth", "sidechain_pump")),
    no_quantize: ENV["NO_QUANTIZE"] == "1" || (family == :wonky && ENV["NO_QUANTIZE"] != "0"),
    golden_swing: ENV["GOLDEN_SWING"] == "1",
    voicing: (ENV["VOICING"] || preset[:voicing] || (family == :wonky ? :quartal : :spread)).to_sym,
    engine_progression: sonic&.dig("harmonic", "engine_progression")&.to_sym,
    half_time_bars: preset[:half_time_bars],
    # INTRO_BARS overrides the preset. There was no way to say "start on the
    # one" — the value came only from the track preset, and SECTION_LAYER_GAIN
    # mutes drums outright for the whole intro (drums: 0.0, sample: 0.55). On a
    # 16-bar beat the default 4 bars is a quarter of the render with no drums
    # under it, and the rap vocal is not section-gated, so it plays alone for
    # ten seconds at 96 BPM before anything joins it.
    #
    # That is the right default for a full track and the wrong one for a loop.
    # INTRO_BARS=0 starts everything on bar one; the default is unchanged.
    intro_bars: (ENV["INTRO_BARS"].to_s.strip.empty? ? nil : ENV["INTRO_BARS"].to_i) ||
                preset.fetch(:intro_bars, family == :wonky ? 8 : 4),
    master_lufs: resolve_master_lufs(family, sonic),
    master_lra: resolve_master_lra(family, sonic),
    # Full darken (1.0) on Wonky was muting kick beater + snare air under pads.
    mood_darken_strength: if family == :dilla
                            deep_render? ? 0.36 : 0.55
                          elsif family == :wonky || camel_mode?
                            0.42
                          else
                            0.75
                          end,
  }
end

# The pad EQ's low-mid gain, in dB.
#
# warm_dilla_pad_post boosted 260 Hz by 2.0 dB and 520 Hz by 1.8 dB (1.2 dB at
# 260 on the fluidsynth branch). That is the middle of the 200-500 Hz band every
# hip-hop mixing source names as "mud" and says to cut -- so the pad was lifted
# exactly where a mix gets congested, and then rolled off at 3.4 kHz where its
# definition lives. Muddy and dull from the same chain.
#
# Measured on an instrumental render, relative to full band: 125 Hz -3.1 dB,
# 250 Hz -5.1, 500 Hz -10.0, 1 kHz -15.1, 2 kHz -21.2, 4 kHz -27.5, 8 kHz -32.8.
# A steady ~6 dB/octave slide with 125 Hz the loudest band. Nothing was clipping
# (crest 12.0 dB, flat factor 0.0), so the "overdrive" was this tilt rather than
# level -- which is why chasing it through the saturation stages found nothing.
#
# Default 0.0: the boosts are removed, not inverted. Operator chose "cut the mud
# boosts" on 2026-08-09; turning them negative would be a tone decision made by
# measurement rather than by ear, which is his call and not this function's.
# PAD_MUD_DB takes a negative number when he wants the actual dip.
#
# The scale argument keeps the three bands' RELATIVE weighting: 520 Hz was 0.9x
# the 260 Hz boost and the fluidsynth branch 0.6x, so a single knob moves all
# three together in the proportion they were tuned in.
def pad_mud_db(scale = 1.0)
  ((ENV["PAD_MUD_DB"] || "0.0").to_f * scale).round(2)
end

# Where render_singers_chop_pads high-passes its pad stem.
#
# Scope note, because the first version of this comment claimed more: this is
# ONE pad path, not the pad bus. The main chain is warm_dilla_pad_post, which
# has no high-pass at all -- so a render that never calls the singers-chop
# renderer is untouched by this, and measuring one proved it (80-140 Hz band
# identical before and after, null residual -41 dB, i.e. render noise).
#
# It is still a real fix, a latent one: the literal 140 was correct while
# build_voicing folded every chord into MIDI 50..62 (147..247 Hz), where the
# filter sat below the lowest root and only removed rumble.
#
# Lowering the chord register to 43..55 (98..196 Hz) for "slower deeper chords"
# broke that relationship silently. Measured: a 98 Hz root through highpass
# f=140 comes out 7.1 dB down (-28.2 dB against -21.1 dB unfiltered). The root
# becomes the QUIETEST note in the chord, so the voicing is heard through its
# upper partials -- thinner and more strident, not deeper. Chasing that as a
# saturation problem is chasing the wrong stage.
#
# Derived from the register rather than pinned, so the two cannot drift apart
# again: whatever CHORD_REGISTER_LOW says, this stays a little below it.
#
# 0.85 of the lowest root, capped at the historical 140 so this can only ever
# open the filter DOWN from where it was, never up into the chords. At the
# default register that is 83 Hz -- still above the sub bus (32..64 Hz) and the
# kick fundamental, so the pads keep out of the low end while keeping their own
# roots.
#
# General mixing practice is to high-pass pads at 150-200 Hz and leave the
# bottom to kick and bass. That advice assumes pads voiced above it. Here the
# operator has deliberately voiced them lower, so the filter follows the music
# rather than the rule of thumb. PAD_HP pins it if that turns out wrong.
def pad_highpass_hz
  pinned = ENV["PAD_HP"].to_s.strip
  return pinned.to_f.clamp(20.0, 400.0).round if pinned =~ /\A[\d.]+\z/

  lowest_root = 440.0 * (2.0**((DillaProducerDNA::CHORD_REGISTER_LOW - 69.0) / 12.0))
  [(lowest_root * 0.85), 140.0].min.clamp(20.0, 140.0).round
end

# How many bars each chord is held for.
#
# Operator direction on 2026-08-09 was "slower deeper chords always". This is
# the "slower" half; CHORD_REGISTER_LOW/HIGH in producer_dna.rb is the "deeper".
#
# The preset value is MULTIPLIED rather than replaced, so the relative shape of
# the catalogue survives: a preset that moved twice as fast as its neighbour
# still does. Measured over TRACK_PRESETS, the distribution was 10 presets at 1
# bar per chord, 55 at 2 and 6 at 4 -- so most of the catalogue changed chord
# every two bars, which at 88 BPM is about 5.5 seconds.
#
# There was no override at all before this: chord_bars came only from the preset
# literal, so there was no way to slow the harmony down short of editing 71
# presets by hand.
#
# CHORD_BARS pins an absolute value, CHORD_SLOWDOWN scales the preset's.
def resolve_chord_bars(preset)
  pinned = ENV["CHORD_BARS"].to_s.strip
  return pinned.to_i.clamp(1, 32) unless pinned.empty? || pinned.to_i.zero?

  base = preset.fetch(:chord_bars, 4)
  factor = (ENV["CHORD_SLOWDOWN"] || "2").to_f
  factor = 1.0 unless factor.positive?
  # Ceil, so a fractional factor still moves a 1-bar preset rather than
  # rounding back down to where it started.
  (base * factor).ceil.clamp(1, 32)
end

def resolve_master_lufs(family, sonic)
  texture = sonic&.dig("synth", "texture").to_s
  return -20.0 if family == :dilla && texture.include?("donuts")
  MASTER_LUFS_BY_STYLE.fetch(family, MASTER_LUFS_BY_STYLE[:default])
end

def resolve_master_lra(family, sonic)
  texture = sonic&.dig("synth", "texture").to_s
  return 14.5 if family == :dilla && texture.include?("donuts")
  LRA_BY_STYLE.fetch(family, LRA_BY_STYLE[:default])
end
