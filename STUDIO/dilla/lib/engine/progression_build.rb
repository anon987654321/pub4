# frozen_string_literal: true
#
# Progression generators: Coltrane changes, tritone subs, backdoors, modal interchange.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.

def chord_from_quality(root_hz, quality, voices: 5)
  intervals = CHORD_TEMPLATES.fetch(quality)
  hz = intervals.map { |iv| (root_hz * (2**(iv / 12.0))).round(2) }
  extra = intervals.max + 2
  hz << (root_hz * (2**(extra / 12.0))).round(2) while hz.length < voices
  hz.sort.first(voices)
end

def chord_intervals_from_hz(hz)
  midis = hz.map { |h| hz_to_midi(h) }.sort
  root = midis.first
  midis.map { |m| ((m - root) % 12).round }.uniq
end

# mode: is accepted and ignored. route_generated_style passes the same four
# keywords to every generator, and this was the one signature that did not take
# it — so the major_third_cycle_full track raised "unknown keyword: :mode" on every render,
# failed its retry, and demo-all substituted a silence placeholder. It shipped
# 33 seconds of silence into the middle of the demo at -70 LUFS.
#
# Ignoring it is correct rather than lazy: Coltrane changes are a fixed cycle of
# major thirds, which is the point of them. They do not vary by mode. The other
# four routes all accept the keyword.
def generate_coltrane_changes(root_hz:, mode: nil, length: 8, seed: nil)
  rng = seed ? Random.new(seed) : Random.new
  offsets = [0, 4, 8] # major thirds
  start = offsets.sample(random: rng)
  Array.new(length) do |i|
    semitone = start + offsets[i % 3]
    root = root_hz * (2**(semitone / 12.0))
    q = %w[maj9 m9 7].sample(random: rng)
    { name: "major_third_cycle_full#{semitone}#{q}", hz: chord_from_quality(root, q) }
  end
end

# Tritone substitution: a dominant (V7) shares its tritone (3rd+7th) with
# the dominant chord a tritone (6 semitones) away, so replacing one for the
# other keeps the same pull toward resolution while the bass moves
# chromatically into the tonic instead of by a 4th/5th. Real, well-defined
# jazz theory (not a producer's signature move) -- substitutes at degree 5
# with sub_chance, same functional-motion engine as generate_progression.
def generate_tritone_sub_progression(root_hz:, mode: :minor, length: 8, seed: nil, sub_chance: 0.45)
  rng = seed ? Random.new(seed) : Random.new
  semitones = SCALE_SEMITONES.fetch(mode)
  quality_for = SCALE_DEGREE_QUALITY.fetch(mode)
  degree = 1
  Array.new(length) do
    substituted = degree == 5 && rng.rand < sub_chance
    chord_root = if substituted
                   root_hz * (2**((semitones[(degree - 1) % 7] + 6) / 12.0))
                 else
                   root_hz * (2**(semitones[(degree - 1) % 7] / 12.0))
                 end
    quality = substituted ? "7" : quality_for.fetch(degree, "m9")
    label = substituted ? "trisub#{degree}7" : "deg#{degree}#{quality}"
    chord = { name: label, hz: chord_from_quality(chord_root, quality) }
    degree = weighted_pick(rng, DEGREE_TRANSITIONS.fetch(degree, { 1 => 1 }))
    chord
  end
end

def generate_backdoor_progression(root_hz:, mode: :minor, length: 8, seed: nil)
  rng = seed ? Random.new(seed) : Random.new
  semitones = SCALE_SEMITONES.fetch(mode)
  degree = 1
  transitions = DEGREE_TRANSITIONS.merge(5 => { 1 => 2, 6 => 4, 4 => 1, 3 => 3 })
  quality_for = SCALE_DEGREE_QUALITY.fetch(mode).merge(4 => "7alt", 7 => "7#11")
  Array.new(length) do
    quality = quality_for.fetch(degree, "m9")
    quality = "7alt" if degree == 5 && rng.rand < 0.35
    chord_root = root_hz * (2**(semitones[(degree - 1) % 7] / 12.0))
    chord = { name: "bk#{degree}#{quality}", hz: chord_from_quality(chord_root, quality) }
    degree = weighted_pick(rng, transitions.fetch(degree, { 1 => 1 }))
    chord
  end
end

def generate_slash_progression(root_hz:, mode: :minor, length: 8, seed: nil)
  rng = seed ? Random.new(seed) : Random.new
  pedal = root_hz
  semitones = SCALE_SEMITONES.fetch(mode)
  degree = 0
  Array.new(length) do
    step = semitones[degree % semitones.length] + (degree / semitones.length) * 12
    upper_root = root_hz * (2**(step / 12.0))
    q = rng.rand < 0.5 ? "maj9" : "m9"
    hz = chord_from_quality(upper_root, q, voices: 4)
    hz[0] = pedal
    degree += weighted_pick(rng, PLANING_STEP_WEIGHTS)
    { name: "slash#{step}#{q}", hz: hz.sort }
  end
end

def generate_modal_interchange(root_hz:, mode: :minor, length: 8, seed: nil)
  rng = seed ? Random.new(seed) : Random.new
  pool = mode == :minor ? [1, 4, 5, 6, 3, 2, 7, 4, 6] : [1, 2, 3, 4, 5, 6, 7, 6, 4]
  semitones = SCALE_SEMITONES.fetch(mode)
  borrow = { 4 => "maj9", 6 => "maj9", 3 => "aug", 7 => "dim" }
  Array.new(length) do |i|
    degree = pool[i % pool.length]
    q = borrow[degree] || SCALE_DEGREE_QUALITY.fetch(mode).fetch(degree, "m9")
    q = PLANING_QUALITIES.sample(random: rng) if rng.rand < 0.2
    root = root_hz * (2**(semitones[(degree - 1) % 7] / 12.0))
    { name: "mod#{degree}#{q}", hz: chord_from_quality(root, q) }
  end
end

# Delegates to DillaHarmony (harmony_engine.rb) so this and hz_to_midi/midi_to_hz
# below can't drift into different rounding, the way theory_runtime.rb's copies
# once did (see its comment) before being fixed the same way.
def root_motion_semitones(a, b)
  DillaHarmony.root_motion_semitones(a, b)
end

# A fugue's recapitulation restating the exposition note-for-note in the
# same voicing reads as static — real recaps land the same material in a
# different register/spacing so the return feels like arrival, not replay.
CONTRAST_VOICINGS = {
  quartal: :drop2, drop2: :cluster, cluster: :spread,
  spread: :quartal, drop3: :spread
}.freeze

def enrich_progression(pads, cfg, phases: [])
  DillaHarmony.enrich_progression(pads, cfg, phases:)
end

def progression_from_engine(sonic, _fallback_mode)
  chord_names = sonic&.dig("harmonic", "engine_chords")
  if chord_names&.any?
    return chord_names.map do |n|
    end.compact
  end
  name = sonic&.dig("harmonic", "engine_progression")&.to_sym
  return unless name && CHORD_PROGRESSIONS.key?(name)
  CHORD_PROGRESSIONS.fetch(name).map do |n|
    PAD_CHORD_LOOKUP[n] || MODAL_MINOR_CHORDS.find { |c| c[:name] == n }
  end.compact
end

def arrange_fugue_progression(pads, needed_chords, cfg)
  return pads if pads.empty?
  hook = pads
  exposition = [(needed_chords * 0.25 / hook.length).ceil, 2].max
  development_len = [(needed_chords * 0.35).round, 2].max
  recapitulation = [(needed_chords * 0.25).round, hook.length].max
  coda = [needed_chords - (exposition * hook.length) - development_len - recapitulation, 0].max

  dev_root = hook.last[:hz].min * (cfg[:style_family] == :flylo ? (2**(3.0 / 12.0)) : 1.0)
  dev_style = case cfg[:progression]
              when :planing then :planing
              when :chromatic_mediant then :chromatic_mediant
              else :functional
              end
  development = case dev_style
                when :planing
                  generate_planing_progression(root_hz: dev_root, length: development_len, seed: stable_hash(cfg[:track]))
                when :chromatic_mediant
                  generate_chromatic_mediant_progression(root_hz: dev_root, length: development_len, seed: stable_hash(cfg[:track]))
                else
                  generate_progression(root_hz: dev_root, mode: :minor, length: development_len, seed: stable_hash(cfg[:track]))
                end

  intro_hook = Array.new(exposition) { hook }.flatten
  recap = hook.first(recapitulation)
  outro = coda.positive? ? (hook * (coda / hook.length.to_f).ceil).first(coda) : []
  arranged = intro_hook + development + recap + outro

  phases = []
  intro_hook.length.times { phases << :exposition }
  development.length.times { phases << :development }
  recap.length.times { phases << :recapitulation }
  outro.length.times { phases << :coda }

  [arranged.first(needed_chords), phases.first(needed_chords)]
end

LA_BEAT_SECTION_STYLES = %i[hook functional chromatic_mediant neo_soul quartal].freeze
# No :planing — generate_planing_progression names like planing0m9 sound random/ugly.
CAMEL_LA_BEAT_STYLES = %i[hook chromatic_mediant functional bridge].freeze
CAMEL_BRIDGE_SYMS = %w[Gm7 Cm11nc Fm9 Bbm9 Eb7 AbMaj13s11 Dmaj9nc DMaj7overG].freeze
CAMEL_FUNCTIONAL_SYMS = %w[Dm9 Gm9 Cm9 Fmaj9 Bbm9 Ebmaj9 Abmaj9 Dbmaj9].freeze
LA_BEAT_MIDI_FX_ROTATE = [
  { cc: 1, rate_hz: 0.22, depth: 52, base: 38, curve: :sine },
  { cc: 74, rate_hz: 0.16, depth: 42, base: 28, curve: :swell },
  { cc: 91, rate_hz: 0.12, depth: 30, base: 22, curve: :sine },
  { cc: 5, rate_hz: 0.18, depth: 24, base: 48, curve: :sine },
  { bend: true, rate_hz: 0.14, depth_cents: 18 },
].freeze

# True when the canonical dilla DNA path is active (RENDER_MODE dilla).
# Historical name camel_mode? kept as alias — camel was merged into dilla.
def dilla_style?
  normalize_render_mode!
  ENV["RENDER_MODE"].to_s.downcase == "dilla"
end
alias camel_mode? dilla_style?

# Single engine mode. Empty RENDER_MODE → dilla. Optional knobs stay as ENV
# (STREAM_COMFORT, RENDER_MODE=warp|long_soul|…), not command aliases.
def normalize_render_mode!
  ENV["RENDER_MODE"] = DEFAULT_RENDER_MODE if ENV["RENDER_MODE"].to_s.strip.empty?
end

def camel_drum_entry_bar
  ENV.fetch("CAMEL_DRUM_ENTRY_BAR", "0").to_i
end

def camel_keep_flylo_on_breakdown?
  ENV.fetch("CAMEL_KEEP_FLYLO", camel_mode? ? "1" : "0") != "0"
end

def la_beat_progression_enabled?
  # Do NOT force LA-beat on Camel — that injected random planing0m9-style
  # chords and made streams sound broken. Opt in: LA_BEAT_PROGRESSION=1.
  ENV.fetch("LA_BEAT_PROGRESSION", "0") != "0"
end

def soul_progression_locked?
  ENV["STREAM_SOUL"] == "1" && ENV.fetch("STREAM_LOCK", "0") == "1"
end

# The progression follows the track unless the caller pinned one.
#
# This stays out of stream(), where it read
# `unless user_pad_locked && ENV["PROGRESSION"] && !ENV["PROGRESSION"].empty?`,
# which skipped the assignment whenever PAD_VOICE or PAD_ARP_MODE was set — and
# PROGRESSION is never empty, because apply_best_defaults! fills it with
# pedal_e_descent. So asking for a specific pad voice silently froze the harmony
# on the default track: `STREAM_TRACK=slum_village_players_documented
# PAD_VOICE=prophet` rendered, and logged, the documented transcription's name
# at its documented 91 BPM while playing pedal_e_descent's chords — D/E, Db/E,
# C/E, Bm/E, Bbm/E, Am/E. curated_progression? was true and the loop arranger
# ran; it looped the wrong six chords faithfully, which is why the render looked
# correct in every log line except the chords themselves.
#
# Same shape as the two failures already recorded in this file (track presets
# overwriting RAP_VOCAL=0, the lead guard inferring intent from LEAD_VOICE
# alone): a guard reading an unrelated key instead of what was actually asked
# for. USER_PINNED_ENV is the thing that knows.
def sync_progression_to_track!(track)
  pinned = USER_PINNED_ENV["PROGRESSION"].to_s
  dmesg("sync progression #{ENV['PROGRESSION'].inspect}→#{pinned.empty? ? track : "(pinned #{pinned})"}",
        unit: "harm0", parent: "dilla0")
  return unless pinned.empty?

  ENV["PROGRESSION"] = track.to_s
end

# LA beat / FlyLo stream — stitch random long sections with variable bar lengths
# instead of looping the first four bars forever.
def arrange_la_beat_progression(pads, needed_chords, cfg)
  return arrange_loop_progression(pads, needed_chords, cfg) + [nil] if pads.empty?

  rng = Random.new(patch_cycle_seed(needed_chords + stable_hash(cfg[:track].to_s)))
  hook = pads
  out = []
  phases = []
  chord_lens = []

  while out.length < needed_chords
    style = LA_BEAT_SECTION_STYLES[rng.rand(LA_BEAT_SECTION_STYLES.length)]
    take = rng.rand(3..8)
    root_hz = (out.last || hook.first)[:hz].min
    section = case style
              when :hook
                hook
              when :functional
                generate_progression(root_hz:, mode: :minor, length: take, seed: rng.rand(1..99_999))
              when :planing
                generate_planing_progression(root_hz:, length: take, seed: rng.rand(1..99_999))
              when :chromatic_mediant
                generate_chromatic_mediant_progression(root_hz:, length: take, seed: rng.rand(1..99_999))
              when :neo_soul, :quartal
                voice_lead_chords(generate_progression(root_hz:, mode: :minor, length: take,
                                                       seed: rng.rand(1..99_999)))
              else
                hook
              end
    section.each do |ch|
      break if out.length >= needed_chords
      out << ch
      phases << %i[exposition main development recapitulation].sample(random: rng)
      chord_lens << rng.rand(1..4)
    end
  end
  [out.first(needed_chords), phases.first(needed_chords), chord_lens.first(needed_chords)]
end

def camel_section_pads(style, hook, root_hz, take, rng)
  case style
  when :hook
    hook
  when :bridge
    bridge = CAMEL_BRIDGE_SYMS.filter_map { |n| learned_chord_pad(n) }
    bridge.length >= 2 ? bridge : hook
  when :chromatic_mediant
    generate_chromatic_mediant_progression(root_hz:, length: take, seed: rng.rand(1..99_999))
  when :functional
    base = CAMEL_FUNCTIONAL_SYMS.filter_map { |n| learned_chord_pad(n) }
    base = curated_progression_pads(:timeless_authentic) if base.length < 4
    base = curated_progression_pads(:maj7_minor_cycle) if base.length < 4
    if base&.length.to_i >= 2
      base.cycle.take(take).to_a
    else
      generate_progression(root_hz:, mode: :minor, length: take, seed: rng.rand(1..99_999))
    end
  when :planing
    generate_planing_progression(root_hz:, length: take, seed: rng.rand(1..99_999))
  else
    hook
  end
end

# Camel stream — chromatic mediant hook + D-minor functional/planing bridges (never 4-bar loop lock).
def arrange_camel_beat_progression(pads, needed_chords, cfg)
  hook = if pads.empty?
           curated_progression_pads(:chromatic_mediant_drift) || []
         else
           pads
         end
  return arrange_loop_progression(hook, needed_chords, cfg) + [nil] if hook.length < 2

  rng = Random.new(patch_cycle_seed(needed_chords + stable_hash(cfg[:track].to_s) + 86))
  out = []
  phases = []
  chord_lens = []
  styles = CAMEL_LA_BEAT_STYLES

  while out.length < needed_chords
    style = styles[rng.rand(styles.length)]
    style = :hook if out.empty?
    take = rng.rand(4..10)
    root_hz = (out.last || hook.first)[:hz].min
    section = camel_section_pads(style, hook, root_hz, take, rng)
    section.each do |ch|
      break if out.length >= needed_chords
      out << ch
      phases << case style
                when :hook then :exposition
                when :bridge then :turn
                when :chromatic_mediant then :development
                when :planing then :build
                else :main
                end
      chord_lens << rng.rand(1..4)
    end
  end
  [out.first(needed_chords), phases.first(needed_chords), chord_lens.first(needed_chords)]
end

# Curated hooks loop as written — no random generative development section
# wedged into the middle of a Donuts/Slum transcription.
def arrange_loop_progression(pads, needed_chords, _cfg)
  return [pads, []] if pads.empty?
  hook = pads
  looped = (hook * (needed_chords.to_f / hook.length).ceil).first(needed_chords)
  total_cycles = (needed_chords.to_f / hook.length).ceil
  phases = looped.each_with_index.map do |_chord, i|
    cycle = i / hook.length
    pos = i % hook.length
    if cycle.zero?
      :exposition
    elsif cycle >= total_cycles - 1 && pos >= [hook.length - 2, 0].max
      :recapitulation
    else
      :main
    end
  end
  [looped, phases]
end

def log_progression_phases!(track, bpm, pads, phases)
  log_progression!(track, bpm, pads, phases)
end
