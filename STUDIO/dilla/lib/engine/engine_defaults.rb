# frozen_string_literal: true
#
# Engine-wide defaults: tempos, chords, stocks, grades, Sonitex and analog chains.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.

GENERATED_STYLE_ROUTES = {
  major_third_cycle_full: :generate_coltrane_changes,
  backdoor: :generate_backdoor_progression,
  slash: :generate_slash_progression,
  modal_interchange: :generate_modal_interchange,
  tritone_sub: :generate_tritone_sub_progression,
}.freeze

def route_generated_style(style, root_hz:, mode:, length:, seed:)
  meth = GENERATED_STYLE_ROUTES[style]
  return send(meth, root_hz:, mode:, length:, seed:) if meth
  nil
end

# The bare-invoke character: the canonical kit-forward DNA — Dilla, and the
# Flying Lotus side of the same lineage.
#
# Briefly defaulted to `ambient` and reverted. Two reasons, and the second is
# the one that matters: it is not what the engine is for, and it broke seven
# TestDilla assertions that read this value rather than setting it. That is the
# tell that the default is part of the engine's contract and not a preference —
# a mode can be added freely, the default cannot be changed quietly.
#
# RENDER_MODE=ambient still selects the ambient bed. It is a mode, not the
# default, and nothing is lost by keeping it that way.
DEFAULT_RENDER_MODE = ENV.fetch("DILLA_DEFAULT_MODE", "dilla").freeze
DEFAULT_BPM = 86.0
DEFAULT_BARS = 88
SAMPLE_RATE = 44_100
BASS_SUSTAIN_SEC = (ENV["BASS_SUSTAIN"] || 1.45).to_f
BASS_DECAY_RATE = (ENV["BASS_DECAY"] || 1.15).to_f
# Level of the synthesised sine bass -- was a hardcoded literal with no knob and
# no entry in HARMONIC_STEM_MIX. Kept at its original 0.30: the bass only ever
# sounded missing because warm_dilla_pad_post's aecho/chorus in_gain:out_gain
# bug was burying the whole harmonic bus ~20 dB. With that fixed, 0.30 puts the
# bass a couple of dB under the drum bus, which is where it belongs; briefly
# raising it to 0.95 (before the real cause was found) put it 8 dB over.
BASS_LEVEL = (ENV["BASS_VOL"] || 0.30).to_f
# Voicemails mix pipeline (make.rb heritage)
VOICEMAILS_BEAT = ENV.fetch("BEAT", File.join(OUTPUT_DIR, "Voicemails.mp3"))
MIX_DUR = 146
MIX_BPM = 118.6
LIVESET_MIN = (ENV["LIVESET_MIN"] || 60).to_i
LIVESET_PERIODS = [97, 113, 127, 149, 163, 179, 193, 211, 227, 251].freeze
# The one vocal source. Every RAP_VOCAL default points here, so it cannot drift
# to whichever take was easiest to process that week. Other slugs remain in the
# catalogue and are still selectable by naming them explicitly -- what changed is
# that nothing reaches them by default or by rotation.
RAP_VOCAL_SOURCE = "gunnhild"

# The voices a demo rotates through when RAP_VOCAL says nothing.
#
# Store P is a rapper the operator works with; haisam_johann and angelo_johann
# are his own recordings; slum_village is the Dilla-lineage reference. Ordered
# so the first slot is a full verse from a working rapper rather than a
# reference or a demo take.
#
# Filtered against the catalogue at use, because a slug that does not resolve
# renders instrumental while the log still prints rap=<slug>.
DEMO_RAP_ROTATION = %w[store_p haisam_johann angelo_johann slum_village jonas_v gunnhild].freeze

# How many entry points into one take a catalogue of tracks may use.
#
# Each rotation slug resolves to exactly one catalogue entry, so it is one
# audio file. Six files over a 451-track demo is still the same voice many
# times over; this decides how far apart two of those land in the
# performance. Part of the fit's cache key, so raising it costs renders
# rather than invalidating what is already on disk.
RAP_VOCAL_VARIANTS = ENV.fetch("RAP_VOCAL_VARIANTS", "24").to_i.clamp(1, 512)

# Whether the launch environment explicitly asked for no vocals.
#
# Four TRACK presets set "RAP_VOCAL" => RAP_VOCAL_SOURCE and are applied with
# force:, so RAP_VOCAL=0 on the command line was overwritten before the render
# ever read it -- asking for no vocals produced a full vocal and a banner that
# cheerfully reported rap=gunnhild. This is the same failure the comment on
# four_seven's profile already describes ("a profile default that silently
# discarded an explicit RAP_VOCAL on the command line made the render look
# like it had ignored the request"), caught then for an explicit ON and
# missed for an explicit OFF.
#
# Captured at load, before any preset runs, because by render time ENV no
# longer distinguishes "operator said 0" from "a preset said gunnhild".
VOCALS_EXPLICITLY_OFF = %w[0 off none].include?(ENV["RAP_VOCAL"].to_s.strip.downcase)

VOCALS = {
  processed: File.join(ROOT, "vocals_processed.wav"),
  precise:   File.join(ROOT, "vocals_precise.wav"),
  original:  File.join(ROOT, "vocals_original_pitch.wav"),
}.freeze
# Analog renderer tuning
ANALOG_ROOTS = [43.65, 49.00, 51.91, 38.89, 46.25].freeze
ANALOG_PRIMES = [97, 109, 127, 149, 167, 191, 223, 251].freeze
ANALOG_CFG = {
  lowpass_hz: 2600,
  sp_bits: 12,
  sp_ratio: 44_100.0 / 26_040.0,
  tape_dc: 0.05,
  chorus_delay_l_ms: 9,
  chorus_delay_r_ms: 13,
  vinyl_level: 0.06,
  bad_tune_spike_cents: 16.0,
}.freeze
TECHNO_BPM = 142
TECHNO_BARS = 8
HEDD = "val(0)+0.28*val(0)*val(0)*(gt(val(0),0)-lt(val(0),0))+0.12*val(0)*val(0)*val(0)|" \
       "val(1)+0.28*val(1)*val(1)*(gt(val(1),0)-lt(val(1),0))+0.12*val(1)*val(1)*val(1)"
PITCH_CLASSES = %w[C Db D Eb E F Gb G Ab A Bb B].freeze
PAD_CHORDS = [
  { name: "Fm9", hz: [174.61, 207.65, 261.63, 311.13, 392.00] },
  { name: "Dbmaj9", hz: [138.59, 174.61, 207.65, 261.63, 311.13] },
  { name: "Cm9", hz: [130.81, 155.56, 196.00, 233.08, 293.66] },
  { name: "Ebmaj9", hz: [155.56, 196.00, 233.08, 293.66, 349.23] },
  { name: "Abmaj9", hz: [207.65, 261.63, 311.13, 392.00, 466.16] },
  { name: "Dm9", hz: [146.83, 174.61, 220.00, 261.63, 329.63] },
  { name: "Gm9", hz: [196.00, 233.08, 293.66, 349.23, 440.00] },
  # "+9" means a natural 9th (C#), not the b9 (C) this had.
  { name: "Bm7b5+9", hz: [123.47, 146.83, 174.61, 220.00, 277.18] },
  { name: "E altered", hz: [164.81, 196.00, 233.08, 293.66, 349.23] },
  { name: "Am9", hz: [110.00, 130.81, 164.81, 196.00, 246.94] },
  { name: "Bbm9", hz: [116.54, 138.59, 174.61, 207.65, 261.63] },
  { name: "Gbmaj9", hz: [92.50, 116.54, 138.59, 174.61, 207.65] },
  { name: "C cluster", hz: [130.81, 138.59, 196.00, 233.08, 311.13] },
  # Was C Eb G Bb Db: a minor third where the major third goes and a b9 on top
  # -- Cm7(b9), which is the one chord this is named for not being. The whole
  # point of the shape is the collision of a major third against a sharp ninth
  # a tenth above it; spelled a semitone down the #9 becomes a plain minor
  # third and the collision it exists for never happens.
  { name: "C7#9 Hendrix", hz: [130.81, 164.81, 196.00, 233.08, 311.13] },
  # Was a byte-for-byte copy of Fmaj9's voicing (b7 instead of maj7, no 13th).
  # Real Fmaj13: root, 3, 5, 13, maj7.
  { name: "Fmaj13", hz: [174.61, 220.00, 261.63, 293.66, 329.63] },
  # Had a b7 (Eb) instead of a major 7th — that's actually F9 (dominant), not
  # Fmaj9. Real Fmaj9: root, 3, 5, maj7 (E), 9.
  { name: "Fmaj9", hz: [174.61, 220.00, 261.63, 329.63, 392.00] },
  { name: "Cmaj9", hz: [130.81, 164.81, 196.00, 246.94, 293.66] },
  { name: "E7b9", hz: [82.41, 103.83, 123.47, 146.83, 174.61] },
  { name: "Bm7b5", hz: [123.47, 146.83, 174.61, 220.00, 261.63] },
  { name: "Em9", hz: [164.81, 196.00, 246.94, 293.66, 369.99] },
  { name: "G7", hz: [196.00, 246.94, 293.66, 349.23, 392.00] },
].freeze
# Get Dis Money / Herbie Sunlight stack — vocoder chords over E pedal (Ethan Hein).
EXTENDED_NINTH_CHORDS = [
  # Was E-G-A-D-G: a 3rd (G) with no 5th and no 9th — not actually a sus4 or
  # a 9 chord despite the name, and the "/D" bass wasn't even in the voicing.
  # Real E9sus4 (root E, 4th A, 5th B, b7 D, 9th F#), keeping the same E
  # pedal bass as every other chord in this table.
  { name: "E9sus4/D", hz: [82.41, 220.00, 246.94, 293.66, 369.99] },
  # Ethan Hein: D/E functions as E9sus4 (Get Dis Money / Come Running To Me).
  # It only functions that way if the F# is in it. Was E D A B D -- E, the 4th,
  # the 5th and a doubled b7, with the ninth that earns the "9" in E9sus4
  # missing and the octave spent doubling a note already there. The D triad the
  # symbol names needs D, F# and A; F# is that ninth.
  { name: "D/E", hz: [82.41, 146.83, 185.00, 220.00, 246.94] },
  { name: "Db/E", hz: [82.41, 277.18, 311.13, 349.23, 415.30] },
  { name: "C/E", hz: [82.41, 261.63, 329.63, 392.00, 493.88] },
  { name: "Bm/E", hz: [82.41, 246.94, 293.66, 369.99, 440.00] },
  { name: "Bbm/E", hz: [82.41, 233.08, 277.18, 349.23, 415.30] },
  { name: "Am/E", hz: [82.41, 220.00, 261.63, 329.63, 392.00] },
  { name: "E9sus4", hz: [82.41, 220.00, 246.94, 293.66, 369.99] },
].freeze
# COMMANDS is derived from the DISPATCH table at the bottom of this file —
# one source of truth for dispatch, help, and the debug introspection dump.
# Analog stock characters — digital signal equivalents of film stock data.
# noise_amp: RMS amplitude of the noise floor (≈tape hiss level)
# sat_drive: tanh waveshaper drive (1.0 = light tube warmth, 3.0 = heavy tape saturation)
# rolloff_hz: high-frequency bandwidth limit (anti-halation backing ↔ tape formulation)
# wow_rate: LFO rate in Hz for pitch modulation (reciprocity failure ↔ capstan speed variance)
# wow_depth: LFO depth [0,1] (tape tension variation)
# warmth_db: low-frequency shelf boost in dB (color temperature ↔ tonal weight)
AUDIO_STOCKS = {
  tape_250:  { noise_amp: 0.0018, sat_drive: 1.4, rolloff_hz: 14_500, wow_rate: 0.40, wow_depth: 0.003, warmth_db: 2.5 },
  tape_500:  { noise_amp: 0.0035, sat_drive: 2.2, rolloff_hz: 12_500, wow_rate: 0.45, wow_depth: 0.004, warmth_db: 4.0 },
  vinyl:     { noise_amp: 0.005, sat_drive: 1.0, rolloff_hz: 18_000, wow_rate: 0.50, wow_depth: 0.015, warmth_db: 2.0 },
  cassette:  { noise_amp: 0.008, sat_drive: 0.8, rolloff_hz: 10_500, wow_rate: 0.50, wow_depth: 0.025, warmth_db: 1.5 },
  acetate:   { noise_amp: 0.011, sat_drive: 1.1, rolloff_hz:  9_500, wow_rate: 0.80, wow_depth: 0.040, warmth_db: 5.0 },
}.freeze

# Analog grade presets — concept map:
# tape_saturation  ↔ H&D film curve (soft-knee waveshaper)
# analog_noise     ↔ Newson-Delon grain (noise floor with midtone envelope)
# harmonic_bloom   ↔ halation (even-harmonic enrichment, energy bleeding adjacent)
# spectral_warmth  ↔ color temperature EQ
# parallel_compress↔ bleach bypass (parallel NY compression)
# multiband_tone   ↔ split toning / split grade
# wow_flutter      ↔ reciprocity failure (pitch/time modulation)
# vinyl_crackle    ↔ faded print (aging artifacts)
# transient_sharpen↔ micro-contrast (presence boost)
# stereo_width     ↔ chromatic aberration (M/S spread)
GRADE_PRESETS = {
  tape_warm:   { fx: %w[spectral_warmth tape_saturation analog_noise transient_sharpen], stock: :tape_250 },
  tape_hot:    { fx: %w[tape_saturation harmonic_bloom analog_noise multiband_tone],      stock: :tape_500 },
  vinyl_press: { fx: %w[spectral_warmth analog_noise wow_flutter vinyl_crackle],          stock: :vinyl    },
  lo_fi:       { fx: %w[spectral_warmth tape_saturation analog_noise wow_flutter],        stock: :cassette },
  broadcast:   { fx: %w[parallel_compress multiband_tone transient_sharpen],              stock: :tape_250 },
  sp1200:      { fx: %w[tape_saturation analog_noise transient_sharpen],                  stock: :tape_500 },
  sonitex:     { fx: %w[spectral_warmth tape_saturation harmonic_bloom analog_noise wow_flutter vinyl_crackle], stock: :acetate },
  vinyl_lab:   { fx: %w[spectral_warmth tape_saturation harmonic_bloom platter_wow vinyl_crackle stylus_mistrack needle_drop_fade analog_noise], stock: :vinyl },
  dub_chamber: { fx: %w[spectral_warmth tape_saturation dub_delay chamber_reverb analog_noise], stock: :tape_500 },
  portastudio: { fx: %w[spectral_warmth tape_saturation wow_flutter analog_noise harmonic_bloom], stock: :cassette },
  shellac:     { fx: %w[spectral_warmth analog_noise vinyl_crackle platter_wow stylus_mistrack], stock: :vinyl },
  night_bus:   { fx: %w[tape_saturation multiband_tone parallel_compress spectral_warmth], stock: :tape_500 },
  hi_fi:       { fx: %w[parallel_compress multiband_tone transient_sharpen stereo_width], stock: :tape_250 },
  spring_room: { fx: %w[spring_reverb spectral_warmth tape_saturation wow_flutter], stock: :acetate },
}.freeze

# Sonitex STX-1260 — Tone Projects lo-fi life-span workstation (VST).
# Signal flow per SOS / Tone Projects: mastering comp → M/S → distortion (tape sat) →
# vinyl bandwidth (resonant head-bump) → wow/flutter → sibilance/phone → noise →
# digital sampler (SP-1200: 12-bit, ~26.04 kHz) → output comp → limiter.
# SP-1200 subset: crush_sr 1.69 → 44100/1.69 ≈ 26095 Hz (KVR / jones-y).
SONITEX_STX1260 = {
  comp_threshold: -22, comp_ratio: 3.4, comp_attack: 18, comp_release: 130, comp_makeup: 2.2,
  stereo_width: 1.16, side_gain: 0.78,
  dist_pre_emph_db: 3.2, dist_pre_lp: 4800, dist_drive: 1.55, dist_mix: 0.68, dist_dc: 0.025,
  hf_rolloff: 13_800, lf_rolloff: 34, head_bump_hz: 64, head_bump_db: 3.0, warmth_db: 2.4,
  groove_wear_lp: 5200,
  wow_rate: 0.26, wow_depth: 0.007, flutter_hz: 4.4, flutter_depth: 0.0045,
  sibilance_db: 1.6, sibilance_hz: 5600, phone_lp: 4400,
  hiss_amp: 0.0028, pop_rate: 0.00035, pop_amp: 0.14, click_rate: 0.0006,
  crush_bits: 12, crush_sr: 1.69, crush_mix: 0.32, crush_post_lp: 3600,
  out_comp_threshold: -19, out_comp_ratio: 2.6, out_comp_makeup: 1.8,
  limit: 0.92, level_out: 0.90,
}.freeze
# Legacy extreme chain (prior STX-1269 emulation) — SONITEX=extreme
SONITEX_STX1269 = {
  comp_threshold: -26, comp_ratio: 5.2, comp_attack: 8, comp_release: 95, comp_makeup: 4.0,
  stereo_width: 1.32, side_gain: 0.62,
  dist_pre_emph_db: 5.5, dist_pre_lp: 3600, dist_drive: 3.1, dist_mix: 0.82, dist_dc: 0.07,
  hf_rolloff: 10_800, lf_rolloff: 45, head_bump_hz: 58, head_bump_db: 5.2, warmth_db: 6.0,
  groove_wear_lp: 3600,
  wow_rate: 0.32, wow_depth: 0.014, flutter_hz: 5.6, flutter_depth: 0.018,
  sibilance_db: 2.8, sibilance_hz: 5200, phone_lp: 3600,
  hiss_amp: 0.0055, pop_rate: 0.0008, pop_amp: 0.22, click_rate: 0.0012,
  crush_bits: 10, crush_sr: 1.69, crush_mix: 0.48, crush_post_lp: 2800,
  out_comp_threshold: -17, out_comp_ratio: 3.2, out_comp_makeup: 2.5,
  limit: 0.86, level_out: 0.88,
}.freeze
SONITEX_PRESETS = {
  classic:  SONITEX_STX1260,
  subtle:   SONITEX_STX1260.merge(
    crush_mix: 0.18, crush_bits: 14, hiss_amp: 0.003, pop_rate: 0.00025, pop_amp: 0.12,
    dist_drive: 1.25, dist_mix: 0.52, wow_depth: 0.004, stereo_width: 1.08
  ),
  scuzz:    SONITEX_STX1260.merge(
    crush_mix: 0.48, crush_bits: 10, hiss_amp: 0.009, pop_rate: 0.0012, pop_amp: 0.32,
    wow_depth: 0.012, dist_drive: 2.1, hf_rolloff: 11_200, warmth_db: 4.2
  ),
  sp1200:   SONITEX_STX1260.merge(
    crush_bits: 12, crush_sr: 1.69, crush_mix: 0.52, crush_post_lp: 3000,
    dist_drive: 1.45, hf_rolloff: 12_600, head_bump_hz: 58, head_bump_db: 3.8
  ),
  cassette: SONITEX_STX1260.merge(
    head_bump_hz: 88, head_bump_db: 4.2, hf_rolloff: 10_800, wow_depth: 0.011,
    flutter_depth: 0.009, hiss_amp: 0.008, warmth_db: 3.6, crush_mix: 0.22
  ),
  extreme:  SONITEX_STX1269,
  donuts_warm: SONITEX_STX1260.merge(
    # hf_rolloff/groove_wear_lp/crush_post_lp all previously sat at
    # 2100-2600Hz — three separate `lowpass=` stages chained back-to-back in
    # dilla_master_filters (see that method), not one filter each tuned in
    # isolation across different commits. Stacked, they compounded into a
    # near-total void from ~2.5kHz to ~19kHz on the whole mix bus (confirmed
    # via sox spectrogram) -- no snare crack, hat shimmer, or vocal presence
    # survived, reading as boxy/muffled/"digital" rather than warm. Widened
    # to stay noticeably darker than donuts_soul (14200/12000/8500) without
    # the total void.
    crush_bits: 12, crush_sr: 1.85, crush_mix: 0.42, crush_post_lp: 6000,
    dist_drive: 1.48, dist_mix: 0.62, hf_rolloff: 7000, groove_wear_lp: 9500,
    head_bump_hz: 58, head_bump_db: 5.2, warmth_db: 5.5, lf_rolloff: 38,
    wow_depth: 0.009, flutter_depth: 0.005, stereo_width: 1.12, hiss_amp: 0.0022,
    out_comp_threshold: -17, out_comp_ratio: 3.2, out_comp_makeup: 2.4,
    limit: 0.86, level_out: 0.88
  ),
  # Stream/soul: warm pad glue + enough air for chords/hats (not a 2 kHz blanket).
  donuts_soul: SONITEX_STX1260.merge(
    crush_bits: 13, crush_sr: 1.4, crush_mix: 0.14, crush_post_lp: 8_500,
    dist_drive: 1.12, dist_mix: 0.32, hf_rolloff: 14_200, groove_wear_lp: 12_000,
    head_bump_hz: 58, head_bump_db: 2.2, warmth_db: 3.0, lf_rolloff: 30,
    wow_depth: 0.0035, flutter_depth: 0.0015, stereo_width: 1.12, hiss_amp: 0.0005,
    phone_lp: 13_500, sibilance_db: 0.8,
    out_comp_threshold: -21, out_comp_ratio: 2.0, out_comp_makeup: 1.2,
    limit: 0.95, level_out: 0.97
  ),
  heavy:    SONITEX_STX1269.merge(
    crush_bits: 8, crush_sr: 2.05, crush_mix: 0.58, crush_post_lp: 2400,
    dist_drive: 3.6, dist_mix: 0.88, dist_pre_emph_db: 6.2, dist_dc: 0.09,
    hiss_amp: 0.006, pop_rate: 0.0009, pop_amp: 0.24, click_rate: 0.0012,
    wow_depth: 0.016, flutter_depth: 0.012, stereo_width: 1.36,
    hf_rolloff: 9600, warmth_db: 7.0, head_bump_db: 6.0, groove_wear_lp: 3200,
    phone_lp: 3100, sibilance_db: 3.4,
    out_comp_threshold: -15, out_comp_ratio: 4.0, out_comp_makeup: 3.0,
    limit: 0.84, level_out: 0.86
  ),
  # Cleaner chain for acoustic grand / Yamaha patches — less crush, more air.
  hi_fi_soul: SONITEX_STX1260.merge(
    crush_bits: 14, crush_sr: 1.15, crush_mix: 0.08, crush_post_lp: 10_000,
    dist_drive: 1.05, dist_mix: 0.22, hf_rolloff: 15_500, groove_wear_lp: 13_500,
    head_bump_hz: 55, head_bump_db: 1.6, warmth_db: 2.0, lf_rolloff: 28,
    wow_depth: 0.002, flutter_depth: 0.001, stereo_width: 1.08, hiss_amp: 0.0003,
    out_comp_threshold: -22, out_comp_ratio: 1.8, out_comp_makeup: 1.0,
    limit: 0.96, level_out: 0.98
  ),
  # Warmer Portastudio-ish — more head bump, mild hiss, gentle wow.
  portastudio: SONITEX_STX1260.merge(
    crush_bits: 12, crush_sr: 1.55, crush_mix: 0.28, crush_post_lp: 5200,
    dist_drive: 1.55, dist_mix: 0.55, hf_rolloff: 9800, groove_wear_lp: 7200,
    head_bump_hz: 72, head_bump_db: 4.8, warmth_db: 4.5, lf_rolloff: 42,
    wow_depth: 0.01, flutter_depth: 0.006, stereo_width: 1.05, hiss_amp: 0.0055,
    out_comp_threshold: -18, out_comp_ratio: 2.8, out_comp_makeup: 2.0,
    limit: 0.9, level_out: 0.9
  ),
  # Shellac / 78rpm dust — more crackle/pop, narrower band.
  shellac_78: SONITEX_STX1260.merge(
    crush_bits: 11, crush_sr: 1.9, crush_mix: 0.4, crush_post_lp: 4500,
    dist_drive: 1.7, dist_mix: 0.6, hf_rolloff: 7200, groove_wear_lp: 5500,
    head_bump_hz: 90, head_bump_db: 3.0, warmth_db: 3.8, lf_rolloff: 80,
    wow_depth: 0.014, flutter_depth: 0.01, stereo_width: 0.92, hiss_amp: 0.007,
    pop_rate: 0.0015, pop_amp: 0.28, click_rate: 0.002,
    out_comp_threshold: -17, out_comp_ratio: 3.0, out_comp_makeup: 2.2,
    limit: 0.88, level_out: 0.88
  ),
  # Night bus — dark, mono-leaning, phone-y.
  night_bus: SONITEX_STX1260.merge(
    crush_bits: 12, crush_sr: 1.6, crush_mix: 0.25, crush_post_lp: 4000,
    dist_drive: 1.4, dist_mix: 0.48, hf_rolloff: 6500, groove_wear_lp: 4800,
    head_bump_hz: 60, head_bump_db: 5.5, warmth_db: 5.0, lf_rolloff: 45,
    wow_depth: 0.008, flutter_depth: 0.004, stereo_width: 0.85, hiss_amp: 0.004,
    phone_lp: 3800, sibilance_db: 2.2,
    out_comp_threshold: -16, out_comp_ratio: 3.5, out_comp_makeup: 2.6,
    limit: 0.87, level_out: 0.89
  ),
}.freeze
# Creative analog grade stacks — post-Sonitex film-stock emulation.
ANALOG_CHAIN_VARIANTS = {
  acetate:    { stock: :acetate,   fx: %w[spectral_warmth tape_saturation harmonic_bloom wow_flutter vinyl_crackle analog_noise] },
  sp1200:     { stock: :tape_500,  fx: %w[tape_saturation multiband_tone transient_sharpen analog_noise stereo_width] },
  cassette:   { stock: :cassette,  fx: %w[spectral_warmth wow_flutter analog_noise vinyl_crackle harmonic_bloom] },
  broadcast:  { stock: :tape_250,  fx: %w[parallel_compress multiband_tone transient_sharpen stereo_width spectral_warmth] },
  lo_fi:      { stock: :cassette,  fx: %w[spectral_warmth tape_saturation wow_flutter harmonic_bloom analog_noise] },
  vinyl_hot:  { stock: :vinyl,     fx: %w[spectral_warmth harmonic_bloom vinyl_crackle platter_wow stylus_mistrack analog_noise stereo_width] },
  sonitex:    { stock: :acetate,   fx: %w[tape_saturation harmonic_bloom wow_flutter vinyl_crackle multiband_tone print_through_echo reel_splice_clicks analog_noise] },
  vinyl_lab:  { stock: :vinyl,     fx: %w[spectral_warmth tape_saturation harmonic_bloom platter_wow vinyl_crackle stylus_mistrack needle_drop_fade analog_noise] },
  dub_chamber: { stock: :tape_500, fx: %w[spectral_warmth tape_saturation dub_delay chamber_reverb haas_jitter analog_noise] },
  # NastyVCS-style "Summing Phasy" (75ips) — console glue + phase width after Sonitex texture.
  # No analog_noise / crackle here: Camel stream already has a light vinyl bed; extra
  # grain stacks into "lots of noise" and buries pads.
  summing_phasy: {
    stock: :tape_250,
    fx: %w[parallel_compress harmonic_bloom stereo_width haas_jitter multiband_tone spectral_warmth tape_saturation],
  },
}.freeze
ANALOG_CHAIN_ROTATE = %i[acetate sp1200 cassette broadcast lo_fi vinyl_hot sonitex vinyl_lab dub_chamber summing_phasy].freeze
# Wild mashups — stream auto-iterate picks from these for authentic analog chaos.
ANALOG_CHAIN_WILD = {
  mpc_donut:     { stock: :tape_500,  fx: %w[tape_saturation harmonic_bloom wow_flutter vinyl_crackle print_through_echo analog_noise] },
  ghost_tape:    { stock: :cassette,  fx: %w[spectral_warmth platter_wow stylus_mistrack needle_drop_fade reel_splice_clicks analog_noise] },
  dub_plate:     { stock: :vinyl,     fx: %w[platter_wow vinyl_crackle dub_delay chamber_reverb haas_jitter harmonic_bloom] },
  spring_haze:   { stock: :acetate,   fx: %w[spring_reverb spectral_warmth tape_saturation wow_flutter stereo_width] },
  sp1200_crush:  { stock: :tape_500,  fx: %w[tape_saturation multiband_tone transient_sharpen analog_noise parallel_compress] },
  broadcast_lab: { stock: :tape_250,  fx: %w[parallel_compress multiband_tone plate_reverb haas_jitter spectral_warmth] },
  chamber_dust:  { stock: :cassette,  fx: %w[chamber_reverb vinyl_crackle wow_flutter harmonic_bloom analog_noise stereo_width] },
}.freeze
ANALOG_CHAIN_WILD_ROTATE = ANALOG_CHAIN_WILD.keys.freeze
SONITEX_ROTATE_STREAM = %i[
  donuts_warm cassette sp1200 subtle scuzz classic heavy
  hi_fi_soul portastudio shellac_78 night_bus donuts_soul
].freeze
CONV_REVERB_ROTATE = %w[chamber plate spring 0].freeze
ANALOG_WILD_STOCKS = %i[tape_500 cassette vinyl acetate tape_250].freeze
GRADE_FX_POOL = %w[
  spectral_warmth tape_saturation harmonic_bloom analog_noise wow_flutter vinyl_crackle
  transient_sharpen stereo_width parallel_compress multiband_tone platter_wow stylus_mistrack
  print_through_echo reel_splice_clicks haas_jitter spring_reverb plate_reverb chamber_reverb dub_delay
].freeze
SOUL_TRACK_FAMILY = %i[
  maj7_minor_cycle quartal_west_coast slow_ballad_wash minor_iv_loop neo_soul neo_soul_pocket
  electronium_loop electronium_classic players_measured warm_minor_arc slash_neo_soul warm_minor_vamp
  modal_quartal_ladder minor_two_five_chain circle_fifths_descent walking_bass_descent
  timeless_authentic jazz_ballad_waltz ii_v_i_major ii_v_i_minor modern_quartal_stack
  fourth_third_sixth_second_turn long_soul golden
].freeze
# Arrangement forms — section lengths in bars (repeats to fill n_bars).
FORM_PRESETS = {
  soul_16: {
    map: [[:intro, 4], [:main, 8], [:build, 4]],
    intro_bars: 4, phrase_bars: 16,
  },
  soul_32: {
    map: [[:intro, 4], [:main, 8], [:build, 8], [:turn, 8], [:outro, 4]],
    intro_bars: 4, phrase_bars: 32,
  },
  donuts_time: {
    map: [[:intro, 4], [:main, 8], [:turn, 8], [:outro, 4]],
    intro_bars: 4, phrase_bars: 16,
  },
  camel_32: {
    map: [[:intro, 8], [:main, 12], [:build, 6], [:turn, 4], [:outro, 2]],
    intro_bars: 8, phrase_bars: 32,
  },
}.freeze
SECTION_KIND_ALIASES = {
  "a" => :main, "a2" => :build, "b" => :turn, "turnaround" => :turn,
}.freeze
# Chains with real vinyl playback (not tape) get a turntable-motor sub-bass rumble bed.
TURNTABLE_RUMBLE_VARIANTS = %i[vinyl_hot vinyl_lab acetate sonitex].freeze
# Internal presets — output filenames use neutral TAPE_RENDER_CATALOG codes only.
TAPE_RENDER_CATALOG = [
  { preset: :syncopated_slash_ninth,      out: "session_01", bars: 63 },
  { preset: :chromatic_planing,         out: "session_02", bars: 64 },
  { preset: :ascending_minor_stack,        out: "session_03", bars: 64 },
  { preset: :minor_soul_loop,            out: "session_04", bars: 64 },
  { preset: :suspended_minor_turn,         out: "session_05", bars: 64 },
  { preset: :major_relative_minor_cycle,            out: "session_06", bars: 64 },
  { preset: :dominant_minor_resolve,       out: "session_07", bars: 64 },
  { preset: :syncopated_slash_alt,     out: "session_08", bars: 63 },
  { preset: :minor_cycle_descent,     out: "session_09", bars: 64 },
  { preset: :minor_stepwise_cycle,         out: "session_10", bars: 64 },
  { preset: :major7_relative_minor_turn,             out: "session_11", bars: 64 },
  { preset: :minor_major_ninth_pair,          out: "session_12", bars: 64 },
  { preset: :minor_stepwise_ascent,            out: "session_13", bars: 64 },
  { preset: :suspended_minor_close, out: "session_14", bars: 64 },
].freeze
INDUSTRIAL_TECHNO_BPM = 135.0
INDUSTRIAL_TECHNO_BARS = 128

# J Dilla / Jay Dee (James Yancey, 1974–2006, Detroit).
# MPC3000 finger-drummed grooves: NOT random "drunk" slop — cyclic, repeating
# microtiming (Charnas: Dilla Time; d-buckner/dilla-time on GitHub).
# Snares/claps land early → hats/kicks/bass feel late (Ethan Hein, Get Dis Money).
# Producer timbre + stereo width dominate hip-hop feel (ar5iv 2410.21297).
#
# Slum Village chord maps sourced from:
#   Ethan Hein — Get Dis Money, Thelonius transcriptions
#   jdillabasslines.wordpress.com — Fantastic Vol. 2 BPM + bass phrasing
#   Hooktheory — Donuts "Time" Ab major IV–iii–vi–ii–V
# Independent micro-timing layers (ms): snare early, kick late, hats later.
# Ranges are cyclic (repeating pocket), not random drunk-slop.
MICROTIMING_MS = {
  kick_anchor: 1..6,
  kick_sync: 6..18,
  snare: -28..-10,
  ghost: -10..6,
  hat_down: -2..8,
  hat_up: 12..32,
  open: 8..20,
  clap: -22..-8,
  bass: 18..34,
  pad: 4..16,
  # Percussion is the one voice that should sound unquantised. Shakers and
  # hand percussion sit late and loose enough to be almost off-beat, against a
  # kick locked to the grid -- the looseness reads as a player only because
  # everything around it is steady. The range is wider than any other role
  # here on purpose: at hat_up's 12..32 it would sound like another hat.
  perc: 22..58,
}.freeze
