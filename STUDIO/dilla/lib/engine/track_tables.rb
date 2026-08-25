# frozen_string_literal: true
#
# Measured sonic profiles, track maps, curated progression names, LUFS/LRA by style.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.

# =============================================================================
# ENHANCEMENT LAYER — sonic profiles, extended harmony, eclectic drums,
# FlyLo sidechain, fugue structure, per-style mastering. (Merged in from the
# former dilla_enhancements.rb — kept as one file per project convention.)
# =============================================================================

# Measured reference sonic profiles (Radio Bergen clips) — inlined so dilla.rb
# has no runtime dependency on radio_bergen_sonic.yml or other sidecar files.
INLINE_SONIC_PROFILES = {
  dilla_timeless: {
    "harmonic" => {
      "engine_progression" => "maj7_minor_cycle",
      "engine_chords" => %w[Dbmaj9 Cm9 Fm9 Bbm9 Ebmaj9 Abmaj9low Bbm9 Ebmaj9],
      "melody_chop_hz" => [659.25, 587.33, 523.25, 440.0, 392.00, 349.23],
    },
    "synth" => {
      "bpm" => 86, "swing" => 0.16, "pad_lowpass_hz" => 3400, "master_lowpass_hz" => 2800,
      "bass_sustain_bar" => 0.94, "bass_shelf_db" => 9, "vinyl_noise" => 0.06,
      "texture" => "donuts_lowpass_warmth",
    },
  },
  flylo_camel: {
    "harmonic" => {
      "engine_progression" => "chromatic_mediant_drift",
      "engine_chords" => %w[Dm9 Cm11nc AbMaj13s11 Gm7 Eb7 A7nc Dmaj9nc DMaj7overG],
    },
    "synth" => {
      "bpm" => 84, "swing" => 0.12, "pad_lowpass_hz" => 3600, "master_lowpass_hz" => 3600,
      "bass_sustain_bar" => 0.88, "bass_shelf_db" => 6, "vinyl_noise" => 0.08,
      "sidechain_pump" => true, "texture" => "jazz_haze_sidechain",
    },
  },
  madlib_eye: {
    "harmonic" => {
      "engine_chords" => %w[Ebmaj7 Ebm7 Cm7 Eb7],
      "melody_chop_hz" => [659.25, 587.33, 523.25, 440.0, 392.00, 349.23],
    },
    "synth" => {
      "bpm" => 96, "swing" => 0.20, "pad_lowpass_hz" => 3200, "master_lowpass_hz" => 3200,
      "bass_sustain_bar" => 0.80, "bass_shelf_db" => 7, "vinyl_noise" => 0.10,
      "crush_mix" => 0.35, "texture" => "sp303_vinyl_grit",
    },
  },
  slum_players: {
    "harmonic" => {
      "engine_progression" => "players_measured",
      "engine_chords" => %w[Dm7 Eb7 Gm7 D7 Eb7 Gm7 Am7],
    },
    "synth" => {
      "bpm" => 93, "swing" => 0.18, "pad_lowpass_hz" => 3300, "master_lowpass_hz" => 3000,
      "bass_sustain_bar" => 0.92, "bass_shelf_db" => 8, "vinyl_noise" => 0.07,
      "texture" => "neo_soul_pocket",
    },
  },
  samiyam_rounded: {
    "harmonic" => {
      "engine_chords" => %w[Dm9 Em7 Ebmaj7 Dm],
    },
    "synth" => {
      "bpm" => 96, "swing" => 0.14, "pad_lowpass_hz" => 3000, "master_lowpass_hz" => 2800,
      "bass_sustain_bar" => 0.85, "bass_shelf_db" => 10, "vinyl_noise" => 0.05,
      "texture" => "modern_dry_punch",
    },
  },
  bergen_akmd_local: {
    "harmonic" => { "engine_progression" => "warm_minor_vamp", "texture" => "bergen_night_rain" },
    "synth" => {
      "bpm" => 87, "swing" => 0.17, "pad_lowpass_hz" => 3100, "master_lowpass_hz" => 2700,
      "bass_shelf_db" => 9, "vinyl_noise" => 0.08, "texture" => "akmd_lofi_mastering",
    },
  },
  chase_swayze_traffic: {
    "harmonic" => { "engine_progression" => "minor_turnaround" },
    "synth" => { "bpm" => 88, "swing" => 0.16, "pad_lowpass_hz" => 3300, "vinyl_noise" => 0.07 },
  },
}.freeze

# playlist.brgen.no study output — inlined so stream mode works without sidecar YAML.
INLINE_RADIO_BERGEN_LEARNINGS = {
  "stream_rotation_weights" => {
    "maj7_minor_cycle" => 14, "neo_soul" => 10, "neo_soul_pocket" => 9, "electronium_loop" => 8,
    "minor_iv_loop" => 7, "players_measured" => 6, "modal_quartal_ladder" => 6, "minor_two_five_chain" => 5,
    "circle_fifths_descent" => 5, "walking_bass_descent" => 5, "warm_minor_arc" => 4,
    "slash_neo_soul" => 4, "warm_minor_vamp" => 3, "timeless_authentic" => 3,
    "fourth_third_sixth_second_turn" => 2, "quartal_west_coast" => 2,
  },
  "stream_env_defaults" => {
    "PERFORMER" => "yancey", "GROOVE_DNA" => "donuts", "SONITEX_PRESET" => "donuts_warm",
    "KICKS" => "1", "SPEAK" => "0" # speech overlay off for now — set SPEAK=1 to re-enable,
  },
  "sonic_profiles" => {
    "bergen_akmd_local" => INLINE_SONIC_PROFILES[:bergen_akmd_local],
    "chase_swayze_traffic" => INLINE_SONIC_PROFILES[:chase_swayze_traffic],
  },
}.freeze

TRACK_SONIC_MAP = {
  timeless: :dilla_timeless,
  maj7_minor_cycle: :dilla_timeless,
  fourth_third_sixth_second_turn: :dilla_timeless,
  timeless_authentic: :dilla_timeless,
  db_major_minor_fall: :dilla_timeless,
  chromatic_minor_descent: :dilla_timeless,
  neo_soul: :dilla_timeless,
  neo_soul_pocket: :slum_players,
  modal_quartal_ladder: :dilla_timeless,
  minor_two_five_chain: :dilla_timeless,
  circle_fifths_descent: :dilla_timeless,
  walking_bass_descent: :dilla_timeless,
  electronium_loop: :dilla_timeless,
  electronium_classic: :dilla_timeless,
  minor_soul_loop: :dilla_timeless,
  voice_led_minor_arc: :dilla_timeless,
  borrowed_dominant_turn: :dilla_timeless,
  soul: :dilla_timeless,
  chromatic_mediant: :flylo_camel,
  chromatic_mediant_drift: :flylo_camel,
  sus_add9_ballad: :madlib_eye,
  generated_mediant: :flylo_camel,
  generated_planing: :dilla_timeless,
  generated: :dilla_timeless,
  players: :slum_players,
  alternating_minor7_pair: :slum_players,
  major7_relative_minor_turn: :slum_players,
}.freeze

# Researched progressions — loop cleanly; skip fugue development + heavy pedal/bitonal.
CURATED_PROGRESSIONS = %i[
  maj7_minor_cycle db_major_minor_fall eb_minor_two_chord minor_iv_loop
  timeless_authentic players_measured fourth_third_sixth_second_turn
  voice_led_minor_arc neo_soul neo_soul_pocket soul minor_soul_loop borrowed_dominant_turn
  chromatic_minor_descent electronium_loop electronium_classic
  syncopated_slash_ninth syncopated_slash_alt sus_add9_ballad
  chromatic_mediant_drift major7_relative_minor_turn alternating_minor7_pair
  minor_dominant_slash_cycle minor_major_ninth_pair minor_ninth_cycle
  jazz baroque suspended_minor_close minor_cycle_descent
  modal_quartal_ladder minor_two_five_chain circle_fifths_descent walking_bass_descent
  phrygian_dominant_descent lament_ground hexatonic_pole_shiver hexatonic_cycle_ring
  dawn_ladder dim_stepping_stone sixth_diminished_wheel augmented_hinge
  lydian_augmented_haze four_station_orbit longing_unresolved neapolitan_door
  sub_ladder_down parallel_ninth_tide slow_pendulum_major picardy_window
  bell_chain_of_fifths double_plagal_open dorian_open_window
].freeze
# still_water_pedal and two_moons_pedal are deliberately NOT curated: the
# comment above says this list skips heavy pedal and bitonal writing, and both
# of them are exactly that. They stay reachable by name, which is the point of
# writing them -- they are just not what the rotation should reach for blind.

FLYLO_TRACKS = %i[
  chromatic_mediant chromatic_mediant_drift sus_add9_ballad
  generated_mediant generated_polytonal generated_neapolitan
].freeze

DILLA_TRACKS = %i[
  timeless chromatic_minor_descent neo_soul syncopated_slash_ninth
  chromatic_planing minor_soul_loop generated_planing generated generated_negative
].freeze

# Pulled down ~3dB across the board + widened LRA — "way too loud" direct
# feedback. loudnorm's integrated-loudness target was landing every track
# at near-broadcast loudness with a tight LRA, which reads as fatiguing
# even when true-peak is technically safe.
# techno is deliberately the same number as :default rather than a louder one.
# It is here so the knob is visible: the genre renderers never had a loudness
# target at all until they were wired to normalise_master!, and an entry reading
# -17.0 is something an operator can find and move. A value invented for it here
# would be a level decision made by measurement rather than by ear.
MASTER_LUFS_BY_STYLE = {
  dilla: -19.0,
  flylo: -17.0,
  madlib: -18.0,
  neo_soul: -18.5,
  # -14, on operator instruction 2026-08-11 ("make it louder, -14 lufs"). The
  # -17 it replaces was set for the Dilla-leaning material this engine started
  # as; techno sits roughly 5 dB above that on any reference, and rendering the
  # techno family through a dilla target landed takes at -19.
  #
  # This also moves DILLA_QUALITY_LUFS_TARGET, which is derived from the spread
  # below rather than written separately. That is the point: without it the
  # quality gate kept its old -20.5..-15.5 window and failed every track the
  # operator had just asked for, reporting the requested level as a defect.
  techno: -14.0,
  # -17.0, which is what analog already renders at. render_analog asks for
  # :analog and there was no :analog, so it took the fetch's :default fallback
  # silently. Written out rather than left implicit: the number does not change,
  # but it stops being a side effect of what :default happens to say, and the
  # operator now has somewhere to put a different one.
  #
  # render_industrial is deliberately not here. It asks for :techno by name, so
  # it masters at techno's level on purpose and tracks it if that moves. Whether
  # industrial should have its own target is a sound decision, not a gap.
  analog: -17.0,
  default: -17.0,
}.freeze

# dilla_quality's acceptable-loudness range, ±1.5dB tolerance around the
# whole intentional style spread above (resolve_master_lufs also drops as
# low as -20.0 for dilla/donuts texture -- covered by the low end here).
DILLA_QUALITY_LUFS_TARGET = ((MASTER_LUFS_BY_STYLE.values.min - 1.5)..(MASTER_LUFS_BY_STYLE.values.max + 1.5)).freeze

LRA_BY_STYLE = {
  dilla: 13.0,
  flylo: 14.0,
  madlib: 13.0,
  neo_soul: 12.0,
  default: 11.0,
}.freeze

VOICING_STYLES = %i[close spread drop2 drop3 quartal cluster].freeze

# Arpeggiator pattern library — each returns degree indices for a chord tone count.
ARP_PATTERN_BUILDERS = {
  up:           ->(n) { (0...n).to_a },
  down:         ->(n) { (0...n).to_a.reverse },
  updown:       ->(n) { seq = (0...n).to_a; seq + seq[1...-1].reverse },
  downup:       ->(n) { seq = (0...n).to_a.reverse; seq + seq[1...-1].reverse },
  skip_up:      ->(n) { (0...n).step(2).to_a + (1...n).step(2).to_a },
  fibonacci:    ->(n) { fib = [0, 1]; fib << fib[-1] + fib[-2] while fib.length < n; fib.first(n).map { |i| i % n } },
  pingpong:     ->(n) { (0...n * 2).map { |i| i < n ? i : (n * 2 - 1 - i) } },
  spiral:       ->(n) { (0...n).flat_map { |i| [i, (i + 2) % n] }.first(n * 2) },
  # Was .first(n), which for a two-note chord took [0, 2] -- and 2 modulo 2 is 0,
  # so the "spread" figure played the same pitch twice. Selecting the degrees
  # that fit keeps the wide-interval shape at every chord size instead of
  # collapsing it at small ones.
  quint_spread: ->(n) { [0, 2, 4, 1, 3].select { |d| d < n } },
  random_walk:  ->(n, rng = Random.new(42)) { cur = 0; Array.new(n * 2) { cur = (cur + rng.rand(-1..1)).clamp(0, n - 1) } },
  euclidean:    ->(n) { hits = 5; steps = n * 2; (0...steps).map { |i| ((i * hits) % steps) < hits ? i % n : nil }.compact },
  major_third_cycle_full:     ->(n) { [0, 2, 1, 3, 2, 0, 1].first(n * 2) },
  donda_stab:   ->(n) { [0, 0, 2, 1].cycle.first(n * 2) },
  flylo_wobble: ->(n) { (0...n).flat_map { |i| [i, i, (i + 1) % n] }.first(n * 3) },
  stutter:      ->(n, rng = Random.new(17)) { (0...[n * 4, 24].max).filter_map do |i| if i.even?
(i / 2) % n
else
(rng.rand < 0.35 ? (i / 3) % n : nil)
end end },
  burst:        ->(n) { [0, 0, 1, 2, 1, 0, 3, 2].cycle.first([n * 3, 18].max) },
  ratchet:      ->(n, rng = Random.new(23)) { base = rng.rand(0...n); (0...[n * 3, 20].max).map { |i| (base + i) % n } },
  # Bubbles rise: each run starts one note higher than the last and climbs to
  # the top, so the figure keeps restarting from further up instead of looping
  # a fixed shape. Repeats of the top note are deliberate -- a bubble reaching
  # the surface sits there a moment before the next one arrives.
  bubble_rise:  ->(n) { (0...n).flat_map { |i| ((i...n).to_a + [n - 1]) }.first([n * 3, 12].max) },
  # Irregular surfacing: mostly the root with sudden darts upward. Seeded, so
  # the same "randomness" comes back on every render -- an accident you cannot
  # reproduce is not a part.
  bubble_pop:   ->(n, rng = Random.new(31)) { Array.new([n * 3, 15].max) { rng.rand < 0.45 ? 0 : rng.rand(0...n) } },

  # --- 2026-07-30: figures with a shape rather than a direction -------------
  #
  # The nineteen above are almost all answers to "which way does it go" -- up,
  # down, up then down, up then down but drunk. These are answers to "what is
  # it doing", which is a different question, and it is the one that separates
  # an arpeggiator from a melody. Each is a real generative rule, not a
  # hand-written figure dressed up: given the same chord you can predict what
  # comes out, and given a different chord it still makes sense.

  # English change ringing. Start with the bells in order and swap adjacent
  # pairs, alternating which pairs, forever: no note repeats within a row and no
  # row repeats until every ordering has been rung. Church towers have been
  # running this algorithm since the 1600s for exactly the reason it works here
  # -- it is the most even way to keep a small set of pitches from ever settling
  # into a pattern the ear can finish.
  plain_hunt: lambda { |n|
    return [0] if n < 2
    row = (0...n).to_a
    rows = [row.dup]
    (2 * n - 1).times do |r|
      row = row.dup
      ((r.even? ? 0 : 1)...(n - 1)).step(2) { |i| row[i], row[i + 1] = row[i + 1], row[i] }
      rows << row
    end
    rows.flatten.first([n * 4, 16].max)
  },
  # Step round the chord by the golden ratio and take what you land on. An
  # irrational step never divides the circle evenly, so the figure never closes
  # -- but because the ratio is the *most* irrational number, the notes still
  # spread as evenly as anything can that is not a cycle. Sunflower seeds pack
  # this way for the same reason.
  golden_rotation: lambda { |n|
    phi = 0.6180339887498949
    Array.new([n * 3, 12].max) { |i| ((i + 1) * phi * n).floor % n }
  },
  # Runs that lengthen and then shorten again: one note, two, three, up to the
  # whole chord, and back down. The chord tones never change, only how far each
  # breath gets before it turns around.
  tide: lambda { |n|
    lengths = (1..n).to_a + (n - 1).downto(1).to_a
    lengths.flat_map { |len| (0...len).to_a }
  },
  # A swing losing energy: the widest interval first, then narrower each pass,
  # spiralling into the middle of the chord and stopping there.
  pendulum: lambda { |n|
    low = 0
    high = n - 1
    out = []
    while low <= high
      out << low
      out << high if high != low
      low += 1
      high -= 1
    end
    out + out.reverse
  },
  # Water down steps: three-note falls, each one starting a step higher than the
  # last, so the figure descends locally and climbs overall.
  cascade: lambda { |n|
    (0...n).flat_map { |start| [start, (start - 1) % n, (start - 2) % n] }
  },
  # Climb patiently, drop all at once. A bird working its way up a thermal and
  # then folding its wings.
  swallow_dive: lambda { |n|
    (1...n).flat_map { |peak| (0..peak).to_a + [0] }
  },
  # Mostly pulled downward, with the occasional wave that pushes back up. The
  # seed is fixed so the same undertow returns every render.
  undertow: lambda { |n, rng = Random.new(53)|
    cur = n - 1
    Array.new([n * 3, 12].max) do
      cur = rng.rand < 0.72 ? (cur - 1) % n : (cur + 2) % n
      cur
    end
  },
  # A phrase and its reply: a rising figure, then the same contour falling, and
  # answered from a different place in the chord so the reply is recognisably
  # the same shape without being the same notes. Two halves the ear can tell
  # apart, which is the one thing an arpeggiator almost never gives you.
  call_answer: lambda { |n|
    call = (0...n).to_a
    call + call.reverse.map { |d| (d + (n / 2)) % n }
  },
  # A short cell repeated, with one note of it advancing each time round. The
  # figure stays recognisable while never being quite the same twice -- prayer
  # beads, where the count changes and the motion does not.
  rosary: lambda { |n|
    (0...n).flat_map { |pass| [0, (1 + pass) % n, (2 + pass) % n] }
  },
  # Momentum rather than randomness: the line keeps travelling in whichever
  # direction it was already going and only occasionally turns, the way a flock
  # changes direction all at once instead of bird by bird.
  murmuration: lambda { |n, rng = Random.new(71)|
    cur = 0
    dir = 1
    Array.new([n * 3, 15].max) do
      dir = -dir if rng.rand < 0.22
      cur = (cur + dir) % n
      cur
    end
  },
}.freeze

# ffmpeg's aecho in_gain scales the DRY signal, not only the echo tail. A patch
# written as aecho=0.28:0.36 therefore loses 18.3 dB against the same chain with
# no echo at all — measured on pink noise, -49.6 dB against -31.3 dB.
#
# That was diagnosed once, in the comment on fm_bowed_pad, and fixed only there.
# A census of the file found 78 of 133 aecho uses still sitting below 0.5 in_gain:
# 45 in 0.4-0.5, 27 in 0.3-0.4, six below 0.3. So most patches were quietly
# attenuating themselves and the handful without a low-gain echo sat on top of
# them — a 30.9 dB spread across the warm role, between patches that rotate
# against each other.
#
# The fix is the one that comment prescribes: keep in_gain near unity and carry
# the echo character in the decays instead. Scaling the decays by the same factor
# preserves the wet/dry ratio rather than just making everything drier, clamped
# because ffmpeg rejects a decay at or above 1.0.
#
# AECHO_NORMALIZE=0 restores the written values exactly.
AECHO_TARGET_IN_GAIN = 0.9
AECHO_MAX_DECAY = 0.9

def normalize_aecho_gains(fx)
  return fx unless fx.is_a?(String) && fx.include?("aecho=")
  return fx if ENV["AECHO_NORMALIZE"] == "0"

  fx.gsub(/aecho=([\d.]+):([\d.]+):([\d.|]+):([\d.|]+)/) do
    in_gain = Regexp.last_match(1).to_f
    out_gain = Regexp.last_match(2)
    delays = Regexp.last_match(3)
    decays = Regexp.last_match(4)
    next Regexp.last_match(0) if in_gain <= 0 || in_gain >= AECHO_TARGET_IN_GAIN

    factor = AECHO_TARGET_IN_GAIN / in_gain
    lifted = decays.split("|").map { |d| [(d.to_f * factor), AECHO_MAX_DECAY].min.round(3) }
    "aecho=#{AECHO_TARGET_IN_GAIN}:#{out_gain}:#{delays}:#{lifted.join('|')}"
  end
end
