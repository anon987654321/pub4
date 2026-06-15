#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Dilla Lab — unified audio engine
# Synthesis, analog pads, vocal mixes (v7–v11), stem rack, demux, MIDI electronium.
#
# Usage: ruby dilla.rb help

require "fileutils"
require "json"
require "open3"

ROOT = File.expand_path(__dir__)
SAMPLE_DIR = File.join(ROOT, "samples")
DRUM_DIR = File.join(SAMPLE_DIR, "drums")
STEM_DIR = File.join(ROOT, "stems")
SAMPLE_CLEAN = File.join(SAMPLE_DIR, "clean_harmonic.wav")
STEM_MIDS = File.join(STEM_DIR, "mids.mp3")
STEM_HIGHS = File.join(STEM_DIR, "highs_pluck.mp3")
STEM_SUB = File.join(STEM_DIR, "sub_bass.mp3")
STEM_CENTER = File.join(STEM_DIR, "center.mp3")
STEM_MANIFEST = File.join(STEM_DIR, "manifest.json")
STEM_EXTS = %w[.mp3 .wav .ogg .flac].freeze
DEMUX_DIR = SAMPLE_DIR
DEMUX_MODEL = "htdemucs_6s"
DEFAULT_BPM = 86.0
DEFAULT_BARS = 88
SAMPLE_RATE = 44_100
# Voicemails mix pipeline (make.rb heritage)
VOICEMAILS_BEAT = ENV.fetch("BEAT", File.join(ROOT, "Voicemails.mp3"))
MIX_DUR = 146
MIX_BPM = 118.6
LIVESET_MIN = (ENV["LIVESET_MIN"] || 60).to_i
LIVESET_PERIODS = [97, 113, 127, 149, 163, 179, 193, 211, 227, 251].freeze
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
  vinyl_level: 0.14,
  bad_tune_spike_cents: 16.0,
}.freeze
HIP_HOP_BPM = 86
HIP_HOP_BARS = 8
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
  { name: "Bm7b5+9", hz: [123.47, 146.83, 174.61, 220.00, 261.63] },
  { name: "E altered", hz: [164.81, 196.00, 233.08, 293.66, 349.23] },
  { name: "Am9", hz: [110.00, 130.81, 164.81, 196.00, 246.94] },
  { name: "Bbm9", hz: [116.54, 138.59, 174.61, 207.65, 261.63] },
  { name: "Gbmaj9", hz: [92.50, 116.54, 138.59, 174.61, 207.65] },
  { name: "C cluster", hz: [130.81, 138.59, 196.00, 233.08, 311.13] },
  { name: "C7#9 Hendrix", hz: [130.81, 155.56, 196.00, 233.08, 277.18] },
  { name: "Fmaj13", hz: [174.61, 220.00, 261.63, 311.13, 392.00] },
  { name: "Fmaj9", hz: [174.61, 220.00, 261.63, 311.13, 392.00] },
  { name: "Em9", hz: [164.81, 196.00, 246.94, 293.66, 369.99] },
  { name: "G7", hz: [196.00, 246.94, 293.66, 349.23, 392.00] }
].freeze
# Get Dis Money / Herbie Sunlight stack — vocoder chords over E pedal (Ethan Hein).
SLUM_VILLAGE_CHORDS = [
  { name: "E9sus4/D", hz: [82.41, 196.00, 220.00, 293.66, 392.00] },
  { name: "Db/E", hz: [82.41, 277.18, 311.13, 349.23, 415.30] },
  { name: "C/E", hz: [82.41, 261.63, 329.63, 392.00, 493.88] },
  { name: "Bm/E", hz: [82.41, 246.94, 293.66, 369.99, 440.00] },
  { name: "Bbm/E", hz: [82.41, 233.08, 277.18, 349.23, 415.30] },
  { name: "Am/E", hz: [82.41, 220.00, 261.63, 329.63, 392.00] },
  { name: "E9sus4", hz: [82.41, 196.00, 220.00, 293.66, 392.00] }
].freeze
COMMANDS = %w[
  help scan sweep council debug sample source livestream separate render verify
  chords clean stems study rhythm melody harmony semantics ears play live bass
  grade grade_list dilla hiphop slum industrial techno analog analog_liveset
  electronium midi mix v7 v8 v9 v10 v11 demux liveset
].freeze
# Analog stock characters — digital signal equivalents of film stock data.
# noise_amp: RMS amplitude of the noise floor (≈tape hiss level)
# sat_drive: tanh waveshaper drive (1.0 = light tube warmth, 3.0 = heavy tape saturation)
# rolloff_hz: high-frequency bandwidth limit (anti-halation backing ↔ tape formulation)
# wow_rate: LFO rate in Hz for pitch modulation (reciprocity failure ↔ capstan speed variance)
# wow_depth: LFO depth [0,1] (tape tension variation)
# warmth_db: low-frequency shelf boost in dB (color temperature ↔ tonal weight)
AUDIO_STOCKS = {
  tape_250:  { noise_amp: 0.003, sat_drive: 1.4, rolloff_hz: 14_500, wow_rate: 0.40, wow_depth: 0.003, warmth_db: 2.5 },
  tape_500:  { noise_amp: 0.006, sat_drive: 2.2, rolloff_hz: 12_500, wow_rate: 0.45, wow_depth: 0.004, warmth_db: 4.0 },
  vinyl:     { noise_amp: 0.009, sat_drive: 1.0, rolloff_hz: 18_000, wow_rate: 0.50, wow_depth: 0.015, warmth_db: 2.0 },
  cassette:  { noise_amp: 0.015, sat_drive: 0.8, rolloff_hz: 10_500, wow_rate: 0.50, wow_depth: 0.025, warmth_db: 1.5 },
  acetate:   { noise_amp: 0.022, sat_drive: 1.1, rolloff_hz:  9_500, wow_rate: 0.80, wow_depth: 0.040, warmth_db: 5.0 },
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
}.freeze

# Sonitex STX-1269 / STX-1260 — Tone Projects extreme lo-fi tape workstation.
# Full life-span chain: bus compression → M/S width → head-bump EQ → wow →
# SP-1200 bit-crush → tape saturation → harmonic bloom → phone-band sibilance →
# hiss/flutter → vinyl pops → HEDD → glue limiter.
SONITEX_STX1269 = {
  comp_threshold: -26, comp_ratio: 5.2, comp_attack: 8, comp_release: 95, comp_makeup: 4.0,
  stereo_width: 1.32, warmth_db: 6.0, rolloff_hz: 10_800, head_bump_hz: 58, head_bump_db: 5.2,
  sat_drive: 3.1, dc_offset: 0.07, crush_bits: 10, crush_sr: 1.69, crush_mix: 0.48,
  wow_rate: 0.32, wow_depth: 0.014, flutter_hz: 5.6, flutter_depth: 0.018,
  hiss_amp: 0.014, pop_rate: 0.0015, pop_amp: 0.38, sibilance_db: 2.8, phone_lp: 3600,
  glue_threshold: -17, glue_ratio: 3.2, limit: 0.86, level_out: 0.88
}.freeze
# Internal presets — output filenames use neutral TAPE_RENDER_CATALOG codes only.
SLUM_VILLAGE_TRACKS = %i[
  get_dis_money thelonious raise_it_up tell_me hold_tight players look_of_love
  forth_and_back conant_gardens i_dont_know climax go_ladies eyes_up untitled_fantastic
].freeze
SLUM_VILLAGE_BARS = { get_dis_money: 63, forth_and_back: 63, tell_me: 64 }.freeze
TAPE_RENDER_CATALOG = [
  { preset: :get_dis_money,      out: "session_01", bars: 63 },
  { preset: :thelonious,         out: "session_02", bars: 64 },
  { preset: :raise_it_up,        out: "session_03", bars: 64 },
  { preset: :tell_me,            out: "session_04", bars: 64 },
  { preset: :hold_tight,         out: "session_05", bars: 64 },
  { preset: :players,            out: "session_06", bars: 64 },
  { preset: :look_of_love,       out: "session_07", bars: 64 },
  { preset: :forth_and_back,     out: "session_08", bars: 63 },
  { preset: :conant_gardens,     out: "session_09", bars: 64 },
  { preset: :i_dont_know,         out: "session_10", bars: 64 },
  { preset: :climax,             out: "session_11", bars: 64 },
  { preset: :go_ladies,          out: "session_12", bars: 64 },
  { preset: :eyes_up,            out: "session_13", bars: 64 },
  { preset: :untitled_fantastic, out: "session_14", bars: 64 }
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
DILLA_TIMING_MS = {
  kick_anchor: 0..5,
  kick_sync: 4..14,
  snare: -18..-6,
  ghost: -10..10,
  hat_down: -3..4,
  hat_up: 12..24,
  bass: 18..32,
  pad: 6..18
}.freeze
DILLA_KICK_PATTERNS = [
  [0, 7, 10, 14],
  [0, 5, 7, 10, 14],
  [0, 3, 7, 10, 12, 14],
  [0, 1, 7, 10, 14],
  [0, 6, 9, 14]
].freeze
DONUT_CHORDS = [
  { name: "Fm9",       hz: [174.61, 207.65, 261.63, 311.13, 392.00] },
  { name: "Dbmaj9",    hz: [138.59, 174.61, 207.65, 261.63, 311.13] },
  { name: "Bbm9",      hz: [116.54, 138.59, 174.61, 207.65, 261.63] },
  { name: "Eb7",       hz: [155.56, 196.00, 233.08, 277.18, 311.13] },
  { name: "Abmaj9low", hz: [103.83, 130.81, 155.56, 196.00, 233.08] },
  { name: "C7b9",      hz: [130.81, 138.59, 164.81, 196.00, 233.08] },
  { name: "Fm/C",      hz: [130.81, 174.61, 207.65, 261.63, 311.13] },
  { name: "Bb7sus",    hz: [116.54, 174.61, 196.00, 233.08, 311.13] }
].freeze
PAD_CHORD_LOOKUP = (
  PAD_CHORDS + SLUM_VILLAGE_CHORDS + DONUT_CHORDS
).each_with_object({}) { |c, m| m[c[:name]] = c unless m[c[:name]] }.freeze
# Album / track progressions — Fantastic Vol. 1 & 2 + Donuts.
DILLA_PROGRESSIONS = {
  soul: %w[Fm9 Dbmaj9 Ebmaj9 Abmaj9],
  donuts: %w[Fm9 Dbmaj9 Bbm9 Eb7 Abmaj9low C7b9 Fm/C Bb7sus],
  donuts_time: %w[Dbmaj9 Cm9 Fm9 Bbm9 Ebmaj9],
  jazz: %w[Dm9 Gm9 C7#9\ Hendrix Fmaj13],
  get_dis_money: %w[E9sus4/D Db/E C/E Bm/E Bbm/E Am/E E9sus4],
  thelonious: %w[Fm9 Bbm9 Fm9 Bbm9],
  raise_it_up: %w[Am9 Dm9 Gm9 Cm9],
  tell_me: %w[Bbm9 Ebmaj9 Abmaj9 Fm9],
  hold_tight: %w[Dm9 Gm9 Cm9 Fmaj9],
  players: %w[Fmaj9 Em9 Am9 Dm9],
  look_of_love: %w[Em9 Am9 Dm9 G7],
  forth_and_back: %w[E9sus4/D C/E Bbm/E Am/E Db/E Bm/E E9sus4],
  conant_gardens: %w[Gm9 Cm9 Fm9 Bbm9],
  i_dont_know: %w[Am9 Dm9 Gm9 Cm9],
  climax: %w[Fm9 Dbmaj9 Ebmaj9 Bbm9],
  go_ladies: %w[Fm9 Bbm9 Ebmaj9 Abmaj9],
  eyes_up: %w[Dm9 Gm9 Cm9 Fmaj9],
  untitled_fantastic: %w[Cm9 Fm9 Bbm9 Ebmaj9]
}.freeze
# Per-track production presets (BPM from jdillabasslines Vol. 2).
DILLA_TRACK_PRESETS = {
  get_dis_money: {
    bpm: 97, progression: :get_dis_money, chord_bars: 1, phrase_bars: 7,
    swing: 54, feel: :get_dis_money, stereo_pan: true,
    timing: { snare: -24..-10, hat_up: 20..36, bass: 28..48, kick_anchor: 0..3 }
  },
  thelonious: {
    bpm: 96, progression: :thelonious, chord_bars: 2, phrase_bars: 2,
    swing: 56, feel: :thelonious,
    timing: { bass: 10..22, pad: -8..4, kick_sync: 6..16 }
  },
  raise_it_up: { bpm: 95, progression: :raise_it_up, chord_bars: 2, swing: 58 },
  tell_me: { bpm: 90, progression: :tell_me, chord_bars: 2, phrase_bars: 8, swing: 55 },
  hold_tight: { bpm: 97, progression: :hold_tight, chord_bars: 2, swing: 57 },
  players: { bpm: 93, progression: :players, chord_bars: 2, swing: 58 },
  look_of_love: { bpm: 92, progression: :look_of_love, chord_bars: 2, swing: 56 },
  forth_and_back: { bpm: 102, progression: :forth_and_back, chord_bars: 1, phrase_bars: 7, swing: 54, feel: :get_dis_money },
  conant_gardens: { bpm: 94, progression: :conant_gardens, chord_bars: 2, swing: 58 },
  i_dont_know: { bpm: 91, progression: :i_dont_know, chord_bars: 2, swing: 62,
                 timing: { bass: 8..28, kick_sync: 2..18 } },
  climax: { bpm: 96, progression: :climax, chord_bars: 2, swing: 57 },
  go_ladies: { bpm: 95, progression: :go_ladies, chord_bars: 2, swing: 58 },
  eyes_up: { bpm: 93, progression: :eyes_up, chord_bars: 4, swing: 55 },
  untitled_fantastic: { bpm: 91, progression: :untitled_fantastic, chord_bars: 2, swing: 56 },
  donuts_time: { bpm: 95, progression: :donuts_time, chord_bars: 2, swing: 52 },
  donuts: { bpm: 86, progression: :donuts, chord_bars: 4, swing: 58 },
  soul: { bpm: 86, progression: :soul, chord_bars: 4, swing: 58 },
  jazz: { bpm: 88, progression: :jazz, chord_bars: 4, swing: 60 }
}.freeze
INDUSTRIAL_BPM_DEFAULT = 132.0

# Dilla Time (Charnas / Flypaper / Soundfly): NOT random slop. Each role has a
# habitual displacement — snares early, upbeat hats late, kicks anchor the grid.
# Roger Linn MPC swing delays even 16ths; Dilla finger-drummed with intentional
# per-hit nudge. Ranges are ms; deterministic from bar/step so loops repeat.
DILLA_TIMING_MS = {
  kick_anchor: 0..5,
  kick_sync: 4..14,
  snare: -18..-6,
  ghost: -10..10,
  hat_down: -3..4,
  hat_up: 12..24,
  bass: 18..32,
  pad: 6..18
}.freeze

DILLA_KICK_PATTERNS = [
  [0, 7, 10, 14],
  [0, 5, 7, 10, 14],
  [0, 3, 7, 10, 12, 14],
  [0, 1, 7, 10, 14],
  [0, 6, 9, 14]
].freeze

PAD_CHORD_LOOKUP = PAD_CHORDS.each_with_object({}) { |chord, memo| memo[chord[:name]] = chord }.freeze
DILLA_PROGRESSIONS = {
  soul: %w[Fm9 Dbmaj9 Ebmaj9 Abmaj9],
  jazz: %w[Dm9 Gm9 C7#9\ Hendrix Fmaj13],
  tritone: %w[Cm9 Gbmaj9 Bbm9 E\ altered]
}.freeze

CHORD_TEMPLATES = {
  "maj" => [0, 4, 7],
  "min" => [0, 3, 7],
  "7" => [0, 4, 7, 10],
  "maj7" => [0, 4, 7, 11],
  "m7" => [0, 3, 7, 10],
  "m9" => [0, 3, 7, 10, 2],
  "maj9" => [0, 4, 7, 11, 2],
  "sus" => [0, 5, 7],
  "dim" => [0, 3, 6]
}.freeze

def sh!(*command)
  puts ">>> #{command.flatten.join(' ')}"
  abort "failed: #{command.flatten.first}" unless system(*command.flatten.map(&:to_s))
end

def capture(*command)
  Open3.capture3(*command.flatten.map(&:to_s))
end

def tool_available?(name)
  ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? { |directory| File.executable?(File.join(directory, name)) }
end

def prompt(label)
  print "#{label}: "
  value = STDIN.gets&.strip
  abort "missing #{label}" if value.nil? || value.empty?
  value
end

# --- FFmpeg expression helpers ---

def lavfi(src)
  ["-f", "lavfi", "-i", src]
end

# Sum ffmpeg aeval expressions; never return empty (ffmpeg rejects blank expr).
def expr_sum(parts)
  flat = parts.flatten.compact.reject { |p| p.to_s.strip.empty? }
  flat.empty? ? "0" : flat.join("+")
end

# Wrap volume envelope for noise-channel gating (snare/hat/open).
def safe_volume_env(parts)
  "(#{expr_sum(parts)})"
end

def chop_hz(chord)
  case chord
  when Hash  then chord[:hz] || chord["hz"] || []
  when Array then chord
  else []
  end
end

# Sample-chop wave: chord may be a PAD_CHORDS Hash or raw Hz array.
def chop_wave(chord, t, v, sustain = 0.55)
  hz = chop_hz(chord)
  return "0" if hz.empty?
  f = hz[(t * 10).to_i % hz.length]
  "between(t,#{t},#{t + sustain})*#{v}*0.11*exp(-(t-#{t})*1.7)*" \
    "(sin(2*PI*#{f}*(t-#{t}))+0.35*sin(2*PI*#{f * 1.5}*(t-#{t})))"
end

def bpm
  (ENV["BPM"] || DEFAULT_BPM).to_f
end

def bars
  (ENV["BARS"] || DEFAULT_BARS).to_i
end

def beat_seconds
  60.0 / bpm
end

def render_seconds
  (beat_seconds * 4.0 * bars).round(3)
end

def chord_expression
  cycle = (PAD_CHORDS.length * 8.0 * beat_seconds).round(4)
  PAD_CHORDS.each_with_index.map do |chord, chord_index|
    start_seconds = chord_index * 8.0 * beat_seconds
    stop_seconds = start_seconds + 8.0 * beat_seconds
    voices = chord[:hz].each_with_index.map do |frequency, voice_index|
      detune = 1.0 + ((voice_index - 2) * 0.0015)
      gain = 0.018 + (voice_index * 0.002)
      "#{gain.round(4)}*sin(2*PI*#{(frequency * detune).round(4)}*t)"
    end.join("+")
    "between(mod(t,#{cycle}),#{start_seconds.round(4)},#{stop_seconds.round(4)})*(#{voices})"
  end.join("+")
end

def start_groove_preview
  return nil unless tool_available?("ffplay")

  tmp = File.join(ROOT, ".groove_tmp.wav")
  render_dilla(tmp, [8, bars].max)
  pid = spawn("ffplay", "-nodisp", "-loop", "0", tmp, out: "/dev/null", err: "/dev/null")
  [pid, tmp]
rescue SystemCallError
  nil
end

def scan(groove: false)
  groove_pid, groove_tmp = groove ? start_groove_preview : [nil, nil]
  puts JSON.pretty_generate(
    root: ROOT,
    bpm: bpm,
    bars: bars,
    seconds: render_seconds,
    files: {
      ruby: File.exist?(__FILE__),
      html: File.exist?(File.join(ROOT, "dilla.html")),
      clean_harmonic: File.exist?(SAMPLE_CLEAN)
    },
    tools: {
      ffmpeg: tool_available?("ffmpeg"),
      ffprobe: tool_available?("ffprobe"),
      yt_dlp: tool_available?("yt-dlp"),
      demucs: tool_available?("demucs")
    },
    commands: COMMANDS
  )
ensure
  if groove_pid
    Process.kill("TERM", groove_pid) rescue nil
    Process.wait(groove_pid) rescue nil
  end
  FileUtils.rm_f(groove_tmp) if groove_tmp
end

def council
  puts "MASTER council"
  puts "preserve existing command surface"
  puts "separate source capture, demucs, rhythm study, melody study"
  puts "add harmony and semantic texture evidence"
  puts "feed ears metrics into MASTER before aesthetic judgment"
  puts "keep render, clean, stems, chords intact"
end

def source(input = nil, output = nil)
  input ||= prompt("audio path or URL")
  output ||= File.join(SAMPLE_DIR, "source.wav")
  FileUtils.mkdir_p(File.dirname(output))
  return convert_audio(input, output) if File.exist?(input)
  download_track(input, output)
end

def livestream(input = nil, output = nil)
  input ||= prompt("livestream URL")
  output ||= File.join(SAMPLE_DIR, "livestream.wav")
  seconds_to_capture = (ENV["LIVE_SECONDS"] || 600).to_i
  abort "yt-dlp required" unless tool_available?("yt-dlp")
  abort "ffmpeg required" unless tool_available?("ffmpeg")
  media_url = direct_media_url(input)
  FileUtils.mkdir_p(File.dirname(output))
  sh! "ffmpeg", "-y", "-t", seconds_to_capture.to_s, "-i", media_url, "-ac", "2", "-ar", SAMPLE_RATE.to_s, "-c:a", "pcm_s16le", output
  puts "wrote #{output}"
  output
end

def sample
  path = source(nil, File.join(SAMPLE_DIR, "source.wav"))
  separated = separate(path)
  harmonic = separated.fetch("other")
  clean(harmonic, SAMPLE_CLEAN)
end

def separate(input = nil)
  input ||= prompt("audio path or URL")
  wav = File.exist?(input) ? input : source(input, File.join(SAMPLE_DIR, "source.wav"))
  abort "demucs required" unless tool_available?("demucs")
  FileUtils.mkdir_p(STEM_DIR)
  sh! "demucs", "-n", "htdemucs_ft", "-o", STEM_DIR, wav
  map = latest_stems
  puts JSON.pretty_generate(map)
  map
end

def latest_stems
  files = Dir[File.join(STEM_DIR, "**", "*.wav")]
  abort "no stems found" if files.empty?
  newest_directory = files.group_by { |path| File.dirname(path) }.max_by { |_directory, paths| paths.map { |path| File.mtime(path) }.max }.first
  stem_paths(Dir[File.join(newest_directory, "*.wav")])
end

def download_track(url, output)
  abort "yt-dlp required" unless tool_available?("yt-dlp")
  abort "ffmpeg required" unless tool_available?("ffmpeg")
  temporary = File.join(SAMPLE_DIR, "download.%(ext)s")
  sh! "yt-dlp", "-f", "bestaudio", "--extract-audio", "--audio-format", "wav", url, "-o", temporary
  downloaded = Dir[File.join(SAMPLE_DIR, "download.wav")].max_by { |path| File.mtime(path) }
  abort "download produced no wav" unless downloaded
  FileUtils.mv(downloaded, output)
  puts "wrote #{output}"
  output
end

def direct_media_url(url)
  output, error, status = capture("yt-dlp", "-g", "-f", "bestaudio", url)
  abort error unless status.success?
  media_url = output.lines.first&.strip
  abort "yt-dlp returned no media URL" if media_url.nil? || media_url.empty?
  media_url
end

def convert_audio(input, output)
  abort "ffmpeg required" unless tool_available?("ffmpeg")
  sh! "ffmpeg", "-y", "-i", input, "-ac", "2", "-ar", SAMPLE_RATE.to_s, "-c:a", "pcm_s16le", output
  puts "wrote #{output}"
  output
end

def render(destination = File.join(ROOT, "full_track.mp3"))
  abort "ffmpeg required" unless tool_available?("ffmpeg")
  FileUtils.mkdir_p(File.dirname(destination))
  duration = render_seconds
  kick_period = (beat_seconds * 2.0).round(6)
  command = ["ffmpeg", "-y"]
  command += ["-f", "lavfi", "-i", "aevalsrc='#{chord_expression}':d=#{duration}:s=#{SAMPLE_RATE}"]
  command += ["-f", "lavfi", "-i", "aevalsrc='0.16*sin(2*PI*49*t)*exp(-mod(t,#{beat_seconds.round(6)})*3.1)':d=#{duration}:s=#{SAMPLE_RATE}"]
  command += ["-f", "lavfi", "-i", "aevalsrc='0.58*sin(2*PI*(45+90*exp(-mod(t,#{kick_period})*18))*t)*exp(-mod(t,#{kick_period})*9)':d=#{duration}:s=#{SAMPLE_RATE}"]
  command += ["-f", "lavfi", "-i", "aevalsrc='0.13*(random(0)-0.5)*lt(mod(t+#{beat_seconds.round(6)},#{kick_period}),0.08)*exp(-mod(t+#{beat_seconds.round(6)},#{kick_period})*28)':d=#{duration}:s=#{SAMPLE_RATE}"]
  command += ["-f", "lavfi", "-i", "aevalsrc='0.035*(random(0)-0.5)*lt(mod(t,#{(beat_seconds / 2.0).round(6)}),0.035)*exp(-mod(t,#{(beat_seconds / 2.0).round(6)})*80)':d=#{duration}:s=#{SAMPLE_RATE}"]
  sample_input = nil
  if File.exist?(SAMPLE_CLEAN)
    sample_input = 5
    command += ["-stream_loop", "-1", "-i", SAMPLE_CLEAN]
  end
  command += ["-filter_complex", render_filter(duration, sample_input), "-map", "[out]", "-t", duration.to_s, *codec_for(destination), destination]
  sh!(*command)
  puts "wrote #{destination}"
end

def render_filter(duration, sample_input)
  filter = []
  filter << "[0:a]aformat=channel_layouts=stereo,lowpass=f=3300,adelay=7|13[ep]"
  filter << "[1:a]aformat=channel_layouts=stereo,lowpass=f=160[bass]"
  filter << "[2:a]aformat=channel_layouts=stereo,lowpass=f=140[kick]"
  filter << "[3:a]aformat=channel_layouts=stereo,highpass=f=900,lowpass=f=5000[snare]"
  filter << "[4:a]aformat=channel_layouts=stereo,highpass=f=6500[hats]"
  labels = %w[[ep] [bass] [kick] [snare] [hats]]
  weights = %w[1.00 0.80 0.72 0.55 0.24]
  if sample_input
    filter << "[#{sample_input}:a]aformat=channel_layouts=stereo,atrim=0:#{duration},asetpts=PTS-STARTPTS,highpass=f=70,lowpass=f=12000[sample]"
    labels << "[sample]"
    weights << "0.85"
  end
  filter << "#{labels.join}amix=inputs=#{labels.length}:weights=#{weights.join(' ')}:duration=first,acompressor=threshold=-18dB:ratio=2.4:attack=24:release=130,acrusher=bits=13:samples=2:mix=0.12,alimiter=limit=0.94:level_out=0.96[out]"
  filter.join(";")
end

def codec_for(destination)
  return ["-codec:a", "libmp3lame", "-b:a", "320k"] if File.extname(destination).downcase == ".mp3"
  ["-c:a", "pcm_s16le"]
end

def verify(path = File.join(ROOT, "full_track.mp3"))
  abort "missing #{path}" unless File.exist?(path)
  output, error, status = capture("ffmpeg", "-hide_banner", "-i", path, "-af", "volumedetect", "-f", "null", "-")
  text = output + error
  puts text.lines.grep(/Duration|bitrate|mean_volume|max_volume/).join
  abort "verify failed" unless status.success? && text.include?("mean_volume:")
end

def clean(input, output)
  abort "missing input" unless input && File.exist?(input)
  FileUtils.mkdir_p(File.dirname(output))
  sh! "ffmpeg", "-y", "-i", input, "-af", "highpass=f=28,lowpass=f=15500,afftdn=nf=-25,adeclick,loudnorm=I=-18:TP=-1.5:LRA=10", "-c:a", "pcm_s16le", output
  puts "wrote #{output}"
end

# --- Stems rack (manifest in stems/) ---

def stems_load_manifest
  return { "active" => "default", "sets" => {} } unless File.exist?(STEM_MANIFEST)
  JSON.parse(File.read(STEM_MANIFEST, encoding: "utf-8"))
end

def stems_write_manifest(manifest)
  File.write(STEM_MANIFEST, JSON.pretty_generate(manifest) + "\n")
  puts "manifest -> #{STEM_MANIFEST}"
end

def stems_scan_set(dir)
  Dir.children(dir).select { |f| STEM_EXTS.include?(File.extname(f).downcase) }.sort
end

def stems_register(name, dir, bpm: nil, source: nil)
  rel = dir.sub(%r{\A#{Regexp.escape(STEM_DIR)}/?}, "")
  rel = "." if rel.empty?
  files = stems_scan_set(dir)
  abort "no stems in #{dir}" if files.empty?
  m = stems_load_manifest
  m["sets"][name] = { "dir" => rel, "bpm" => bpm, "source" => source, "files" => files }.compact
  m["active"] ||= name
  stems_write_manifest(m)
end

def stems_scan(root = File.join(SAMPLE_DIR, "demucs"), manifest = File.join(SAMPLE_DIR, "manifest.json"))
  grouped = Dir.glob(File.join(root, "**", "*.{wav,mp3,flac,ogg,m4a}"), File::FNM_EXTGLOB)
               .group_by { |path| File.dirname(path) }
  sets = grouped.map.with_index do |(directory, files), index|
    {
      "name" => File.basename(directory),
      "bpm" => bpm,
      "stems" => stem_paths(files),
      "prime_swell" => ANALOG_PRIMES[index % ANALOG_PRIMES.length]
    }
  end
  FileUtils.mkdir_p(File.dirname(manifest))
  File.write(manifest, JSON.pretty_generate({ "version" => 4, "sets" => sets }) + "\n")
  puts "manifest -> #{manifest}"
end

def stems(*args)
  case args[0]
  when "scan"
    stems_scan(args[1] || File.join(SAMPLE_DIR, "demucs"), args[2] || File.join(SAMPLE_DIR, "manifest.json"))
  when "add"
    name = args[1] or abort "usage: ruby dilla.rb stems add <name> <dir> [bpm]"
    dir  = args[2] or abort "usage: ruby dilla.rb stems add <name> <dir> [bpm]"
    stems_register(name, File.expand_path(dir), bpm: (args[3] && args[3].to_f))
  when nil
    stems_register("default", STEM_DIR, bpm: 90, source: "Sirkel Sag · Voicemails")
  else
    stems_scan(args[0], args[1] || STEM_MANIFEST)
  end
end

def stem_paths(files)
  files.each_with_object({}) { |path, map| map[stem_key(path)] = path.sub(ROOT + "/", "") }
end

def stem_key(path)
  basename = File.basename(path).downcase
  return "drums" if basename.include?("drums")
  return "bass" if basename.include?("bass")
  return "vocals" if basename.include?("vocals")
  return "other" if basename.include?("other")
  File.basename(path, ".*")
end

def chords
  PAD_CHORDS.each_with_index { |chord, number| puts "%02d %s %s" % [number + 1, chord[:name], chord[:hz].map { |frequency| frequency.round(2) }.join(" ")] }
end

def study(kind, input = nil)
  input ||= prompt("audio path")
  abort "missing #{input}" unless File.exist?(input)
  return rhythm(input) if kind == "rhythm"
  return melody(input) if kind == "melody"
  return harmony(input) if kind == "harmony"
  return semantics(input) if kind == "semantics"
  abort "study kind must be rhythm, melody, harmony, or semantics"
end

def rhythm(input = nil)
  input ||= prompt("drum or full audio path")
  data = frame_energy(input, highpass: 90, lowpass: 8_000)
  peaks = peak_frames(data.fetch(:frames), data.fetch(:hop_seconds))
  puts JSON.pretty_generate(type: "rhythm", path: input, duration_seconds: data.fetch(:duration_seconds), peaks: peaks.first(128))
end

def melody(input = nil)
  input ||= prompt("melodic stem path")
  data = spectral_windows(input)
  puts JSON.pretty_generate(type: "melody", path: input, duration_seconds: data.fetch(:duration_seconds), windows: data.fetch(:windows).first(128))
end

def harmony(input = nil)
  input ||= prompt("harmonic stem path")
  profile = pitch_profile(input)
  ranking = chord_candidates(profile.fetch(:pitch_classes)).first(16)
  puts JSON.pretty_generate(type: "harmony", path: input, duration_seconds: profile.fetch(:duration_seconds), pitch_classes: profile.fetch(:pitch_classes), chords: ranking)
end

def semantics(input = nil)
  input ||= prompt("audio path")
  rhythm_data = frame_energy(input, highpass: 60, lowpass: 12_000)
  loudness = rhythm_data.fetch(:frames).map(&:last)
  brightness = frame_energy(input, highpass: 2_400, lowpass: 12_000).fetch(:frames).map(&:last)
  density = peak_frames(rhythm_data.fetch(:frames), rhythm_data.fetch(:hop_seconds)).length.to_f / [rhythm_data.fetch(:duration_seconds), 1.0].max
  puts JSON.pretty_generate(type: "semantics", path: input, duration_seconds: rhythm_data.fetch(:duration_seconds), tags: semantic_tags(loudness, brightness, density))
end

def ears(path = File.join(ROOT, "full_track.mp3"))
  abort "missing #{path}" unless File.exist?(path)
  report = media_metadata(path).merge(volume_metadata(path)).merge(path: path)
  report[:verdict] = ears_verdict(report)
  puts JSON.pretty_generate(report)
end

def frame_energy(path, highpass:, lowpass:)
  abort "ffmpeg required" unless tool_available?("ffmpeg")
  raw = pipe_floats(path, "highpass=f=#{highpass},lowpass=f=#{lowpass},aformat=sample_fmts=flt:channel_layouts=mono")
  hop = 2_048
  frames = raw.each_slice(hop).with_index.map do |slice, index|
    next if slice.empty?
    [index * hop.to_f / SAMPLE_RATE, Math.sqrt(slice.sum { |value| value * value } / slice.length)]
  end.compact
  { frames: frames, hop_seconds: hop.to_f / SAMPLE_RATE, duration_seconds: raw.length.to_f / SAMPLE_RATE }
end

def spectral_windows(path)
  raw = pipe_floats(path, "highpass=f=90,lowpass=f=5000,aformat=sample_fmts=flt:channel_layouts=mono")
  window = 4_096
  windows = raw.each_slice(window).with_index.map do |slice, index|
    next if slice.length < window
    zero_crossings = slice.each_cons(2).count { |left, right| (left.negative? && right.positive?) || (left.positive? && right.negative?) }
    estimated_hz = zero_crossings.to_f * SAMPLE_RATE / (2.0 * slice.length)
    [index * window.to_f / SAMPLE_RATE, estimated_hz.round(2), nearest_note(estimated_hz)]
  end.compact
  { duration_seconds: raw.length.to_f / SAMPLE_RATE, windows: windows }
end

def pitch_profile(path)
  raw = pipe_floats(path, "highpass=f=65,lowpass=f=5000,aformat=sample_fmts=flt:channel_layouts=mono")
  window = 2_048
  bins = Array.new(12, 0.0)
  raw.each_slice(window) do |slice|
    next if slice.length < window
    estimate = zero_crossing_hz(slice)
    next if estimate < 40.0 || estimate > 5_000.0
    bins[pitch_class_for(estimate)] += slice.sum { |value| value.abs } / slice.length
  end
  total = bins.sum
  normalized = total.positive? ? bins.map { |value| (value / total).round(5) } : bins
  { duration_seconds: raw.length.to_f / SAMPLE_RATE, pitch_classes: PITCH_CLASSES.zip(normalized).to_h }
end

def chord_candidates(pitch_classes)
  values = PITCH_CLASSES.map { |name| pitch_classes.fetch(name, 0.0) }
  candidates = []
  PITCH_CLASSES.each_with_index do |root_name, root_index|
    CHORD_TEMPLATES.each do |suffix, intervals|
      score = intervals.sum { |interval| values[(root_index + interval) % 12] }
      candidates << { chord: "#{root_name}#{suffix}", score: score.round(5) }
    end
  end
  candidates.sort_by { |candidate| -candidate.fetch(:score) }
end

def zero_crossing_hz(slice)
  crossings = slice.each_cons(2).count { |left, right| (left.negative? && right.positive?) || (left.positive? && right.negative?) }
  crossings.to_f * SAMPLE_RATE / (2.0 * slice.length)
end

def pitch_class_for(frequency)
  (69 + (12 * Math.log2(frequency / 440.0))).round % 12
end

def semantic_tags(loudness, brightness, density)
  mean_loudness = average(loudness)
  mean_brightness = average(brightness)
  tags = []
  tags << (density > 2.5 ? "dense" : "spacious")
  tags << (mean_brightness > mean_loudness * 0.45 ? "bright" : "warm")
  tags << (standard_deviation(loudness) > mean_loudness * 0.8 ? "unstable" : "steady")
  tags << (mean_loudness < 0.03 ? "intimate" : "forward")
  tags
end

def pipe_floats(path, filter)
  output, error, status = capture("ffmpeg", "-v", "error", "-i", path, "-af", filter, "-f", "f32le", "-")
  abort error unless status.success?
  output.unpack("e*")
end

def peak_frames(frames, hop_seconds)
  return [] if frames.empty?
  values = frames.map(&:last)
  threshold = average(values) + standard_deviation(values)
  frames.each_cons(3).each_with_object([]) do |(left, middle, right), out|
    next unless middle.last > threshold && middle.last > left.last && middle.last > right.last
    out << { time: middle.first.round(3), strength: middle.last.round(5), grid: (middle.first / hop_seconds).round }
  end
end

def average(values)
  return 0.0 if values.empty?
  values.sum / values.length
end

def standard_deviation(values)
  mean = average(values)
  Math.sqrt(values.sum { |value| (value - mean) * (value - mean) } / [values.length, 1].max)
end

def nearest_note(frequency)
  return nil if frequency <= 0
  midi = (69 + (12 * Math.log2(frequency / 440.0))).round
  "#{PITCH_CLASSES[midi % 12]}#{(midi / 12) - 1}"
end

def media_metadata(path)
  output, error, status = capture("ffprobe", "-v", "error", "-show_entries", "format=duration,bit_rate", "-of", "json", path)
  abort error unless status.success?
  format = JSON.parse(output).fetch("format", {})
  { duration_seconds: format.fetch("duration", "0").to_f.round(3), bit_rate: format.fetch("bit_rate", "0").to_i }
rescue JSON::ParserError => error
  abort "ffprobe json parse failed: #{error.message}"
end

def volume_metadata(path)
  output, error, status = capture("ffmpeg", "-hide_banner", "-i", path, "-af", "volumedetect", "-f", "null", "-")
  abort error unless status.success?
  text = output + error
  { mean_volume_db: number_after(text, "mean_volume:"), max_volume_db: number_after(text, "max_volume:") }
end

def number_after(text, label)
  line = text.lines.find { |entry| entry.include?(label) }
  line ? line.split(label, 2).last.to_f : nil
end

def ears_verdict(report)
  return "too_short" if report[:duration_seconds] < 20.0
  return "too_quiet" if report[:mean_volume_db] && report[:mean_volume_db] < -28.0
  return "clips" if report[:max_volume_db] && report[:max_volume_db] > -0.2
  "usable"
end

def debug
  scan
  _output, error, status = capture("ruby", "-c", __FILE__)
  puts(status.success? ? "ruby syntax: ok" : error)
end

def sweep
  output = File.join(ROOT, "sweep_check.mp3")
  previous = ENV["BARS"]
  ENV["BARS"] = "8"
  render(output)
  verify(output)
  ears(output) if tool_available?("ffprobe")
ensure
  previous ? ENV["BARS"] = previous : ENV.delete("BARS")
end

# --- Analog grade engine ---

# Build an ffmpeg filter fragment for one grade effect using stock params.
# Each filter maps to a postpro analog concept (see GRADE_PRESETS comment).
def grade_filter(fx, stock)
  case fx
  when "tape_saturation"
    # H&D characteristic curve analog: tanh waveshaper, gain-neutral.
    d = stock[:sat_drive]
    n = Math.tanh(d).round(6)
    "aeval=exprs='tanh(#{d}*val(0))/#{n}:tanh(#{d}*val(1))/#{n}'"
  when "analog_noise"
    # Newson-Delon grain analog: flat Gaussian noise floor at stock amplitude.
    a = stock[:noise_amp]
    "aeval=exprs='val(0)+#{a}*(random(0)-0.5):val(1)+#{a}*(random(1)-0.5)'"
  when "harmonic_bloom"
    # Halation analog: even-harmonic enrichment (tube/transformer bloom).
    # x|x| adds 2nd+3rd order harmonics without DC offset.
    "aeval=exprs='val(0)+0.07*val(0)*abs(val(0)):val(1)+0.07*val(1)*abs(val(1))'"
  when "spectral_warmth"
    # Color temperature analog: low-shelf boost + high-shelf cut.
    db  = stock[:warmth_db].round(1)
    cut = (db * 0.65).round(1)
    "equalizer=f=90:width_type=o:width=2:g=#{db},equalizer=f=9500:width_type=o:width=2:g=-#{cut}"
  when "parallel_compress"
    # Bleach bypass analog: New York parallel compression.
    "acompressor=threshold=-22dB:ratio=7:attack=6:release=55:makeup=3:mix=0.45"
  when "multiband_tone"
    # Split grade analog: three-band independent tonal shaping.
    "equalizer=f=110:width_type=o:width=2:g=1.8,equalizer=f=900:width_type=o:width=2:g=0.5,equalizer=f=7000:width_type=o:width=2:g=-1.2"
  when "wow_flutter"
    # Reciprocity failure analog: capstan speed LFO (wow=slow, flutter=fast).
    r = stock[:wow_rate]
    d = stock[:wow_depth]
    "vibrato=f=#{r}:d=#{d}"
  when "vinyl_crackle"
    # Faded print analog: stochastic crackle bursts at ~0.08% of samples.
    "aeval=exprs='val(0)+(random(0)<8e-4?(random(1)-0.5)*0.22:0):val(1)+(random(2)<8e-4?(random(3)-0.5)*0.22:0)'"
  when "transient_sharpen"
    # Micro-contrast analog: presence boost via high-mid shelf.
    "equalizer=f=4000:width_type=o:width=1.5:g=2.0"
  when "stereo_width"
    # Chromatic aberration analog: M/S stereo widening.
    "extrastereo=m=1.35"
  end
end

def sonitex_enabled?
  ENV.fetch("SONITEX", "1") !~ /\A(?:0|false|off)\z/i
end

# Master-bus Sonitex STX-1269 chain (ffmpeg filter_complex segments).
def sonitex_tape_filters(input_tag = "mix")
  unless sonitex_enabled?
    return ["[#{input_tag}]alimiter=limit=0.90:level_out=0.92[out]"]
  end
  s = SONITEX_STX1269
  d = s[:sat_drive]
  n = Math.tanh(d).round(6)
  [
    "[#{input_tag}]acompressor=threshold=#{s[:comp_threshold]}dB:ratio=#{s[:comp_ratio]}:attack=#{s[:comp_attack]}:release=#{s[:comp_release]}:makeup=#{s[:comp_makeup]}[snx1]",
    "[snx1]extrastereo=m=#{s[:stereo_width]}[snx2]",
    "[snx2]equalizer=f=#{s[:head_bump_hz]}:t=o:w=0.85:g=#{s[:head_bump_db]},equalizer=f=85:t=o:w=2:g=#{s[:warmth_db]},equalizer=f=#{s[:rolloff_hz]}:t=o:w=2:g=-4.2[snx3]",
    "[snx3]vibrato=f=#{s[:wow_rate]}:d=#{s[:wow_depth]}[snx4]",
    "[snx4]acrusher=bits=#{s[:crush_bits]}:samples=#{s[:crush_sr]}:mix=#{s[:crush_mix]}[snx5]",
    "[snx5]aeval=exprs='tanh(#{d}*(val(0)+#{s[:dc_offset]}))/#{n}|tanh(#{d}*(val(1)+#{s[:dc_offset]}))/#{n}'[snx6]",
    "[snx6]aeval=exprs='val(0)+0.1*val(0)*abs(val(0))|val(1)+0.1*val(1)*abs(val(1))'[snx7]",
    "[snx7]lowpass=f=#{s[:phone_lp]},equalizer=f=5200:t=o:w=1.3:g=#{s[:sibilance_db]}[snx8]",
    "[snx8]aeval=exprs='(val(0)+#{s[:hiss_amp]}*(random(0)-0.5))*(1+#{s[:flutter_depth]}*sin(2*PI*#{s[:flutter_hz]}*t))|" \
    "(val(1)+#{s[:hiss_amp]}*(random(1)-0.5))*(1+#{s[:flutter_depth]}*sin(2*PI*#{s[:flutter_hz]}*t+0.7))'[snx9]",
    "[snx9]aeval=exprs='val(0)+if(lt(random(2),#{s[:pop_rate]}),(random(3)-0.5)*#{s[:pop_amp]},0)|" \
    "val(1)+if(lt(random(4),#{s[:pop_rate]}),(random(5)-0.5)*#{s[:pop_amp]},0)'[snx10]",
    "[snx10]aeval=exprs='#{HEDD}'[snx11]",
    "[snx11]acompressor=threshold=#{s[:glue_threshold]}dB:ratio=#{s[:glue_ratio]}:attack=18:release=110:makeup=2.5[snx12]",
    "[snx12]alimiter=limit=#{s[:limit]}:level_out=#{s[:level_out]}[out]"
  ]
end

def grade(input = nil, output = nil, preset_name = nil)
  input       ||= prompt("audio path")
  preset_name ||= prompt("preset (#{GRADE_PRESETS.keys.join(', ')})")
  output      ||= input.sub(/(\.\w+)\z/, "_#{preset_name}\\1")
  abort "missing #{input}" unless File.exist?(input)
  p = GRADE_PRESETS[preset_name.to_sym] or abort "unknown preset: #{preset_name}. valid: #{GRADE_PRESETS.keys.join(', ')}"
  stock   = AUDIO_STOCKS[p[:stock]]
  filters = p[:fx].filter_map { |fx| grade_filter(fx, stock) }
  abort "no filters for preset #{preset_name}" if filters.empty?
  chain = [filters, "lowpass=f=#{stock[:rolloff_hz]}"].flatten.join(",")
  sh! "ffmpeg", "-y", "-i", input, "-af", chain, "-c:a", "pcm_s16le", output
  puts "wrote #{output}"
end

def grade_list
  GRADE_PRESETS.each do |name, p|
    stock = p[:stock]
    puts "#{name}: #{p[:fx].join(' → ')} [#{stock}]"
  end
end

# --- Live playback ---

# Render a short preview and play it immediately via ffplay.
def play(preset_name = nil, bars_count = 8)
  abort "ffplay required" unless tool_available?("ffplay")
  preset_name ||= "dilla"
  tmp = File.join(ROOT, ".play_tmp.mp3")
  prev = ENV["BARS"]
  ENV["BARS"] = bars_count.to_s
  if preset_name == "dilla"
    render_dilla(tmp)
  else
    render(tmp)
  end
  sh! "ffplay", "-nodisp", "-autoexit", tmp
ensure
  prev ? ENV["BARS"] = prev : ENV.delete("BARS")
  FileUtils.rm_f(tmp)
end

# Stream audio live from ffplay without writing a file — generative beat.
def live(bars_count = 32)
  abort "ffplay required" unless tool_available?("ffplay")
  tmp = File.join(ROOT, ".live_tmp.wav")
  render_dilla(tmp, bars_count)
  puts "streaming #{bars_count} bars... Ctrl-C to stop"
  exec "ffplay", "-nodisp", "-loop", "0", tmp
rescue SystemCallError => e
  abort "ffplay failed: #{e.message}"
end

# Instantly play a modulating bass tone — good for local audio system check.
def bass(root_hz = 55.0)
  abort "ffplay required" unless tool_available?("ffplay")
  # Warbling sub bass: fundamental + slow pitch LFO + low harmonic content.
  # Models J Dilla's low-end: not a clean sine, has movement and weight.
  lfo_hz   = 0.18
  lfo_amt  = root_hz * 0.04
  expr_l   = "0.45*sin(2*PI*(#{root_hz}+#{lfo_amt}*sin(2*PI*#{lfo_hz}*t))*t)" \
             "+0.08*sin(2*PI*#{(root_hz * 2).round(2)}*t)" \
             "+0.03*sin(2*PI*#{(root_hz * 3).round(2)}*t)"
  filter = "aeval=exprs='#{expr_l}:#{expr_l}',equalizer=f=80:width_type=o:width=2:g=4,lowpass=f=200"
  puts "playing bass #{root_hz}Hz (Ctrl-C to stop)"
  exec "ffplay", "-f", "lavfi", "-i", "aevalsrc=0", "-nodisp", "-af", filter
rescue SystemCallError => e
  abort "ffplay failed: #{e.message}"
end

# --- J Dilla Time beat engine (MPC3000 cyclic microtiming) ---

def dilla_timing_ms(role, bar_index, step_index, timing = nil)
  range = timing&.fetch(role, nil) || DILLA_TIMING_MS.fetch(role)
  seed  = (bar_index * 97) + (step_index * 31) + role.hash.abs
  range.begin + (seed % (range.end - range.begin + 1))
end

def dilla_resolve_config
  track = (ENV["TRACK"] || ENV["PROGRESSION"] || "donuts").to_s.downcase.tr("-", "_").to_sym
  preset = DILLA_TRACK_PRESETS.fetch(track, DILLA_TRACK_PRESETS[:donuts])
  {
    track: track,
    bpm: (ENV["BPM"] || preset[:bpm] || DEFAULT_BPM).to_f,
    progression: preset.fetch(:progression, track),
    chord_bars: preset.fetch(:chord_bars, 4),
    phrase_bars: preset[:phrase_bars],
    swing: (ENV["SWING"] || preset.fetch(:swing, 58)).to_f,
    feel: preset[:feel] || :default,
    stereo_pan: preset[:stereo_pan] || false,
    timing: preset[:timing]
  }
end

def dilla_chord_index(bar, pad_chords, chord_bars:, phrase_bars: nil)
  if phrase_bars
    (bar % phrase_bars) % pad_chords.length
  else
    (bar / chord_bars) % pad_chords.length
  end
end

def dilla_swing_offset(step_index, step_p, swing)
  return 0.0 if swing.to_f <= 0.0 || step_index.even?
  (step_p * swing.clamp(0.0, 100.0) / 100.0 * 0.5).round(6)
end

def dilla_velocity(base, bar_index, step_index, spread: 0.10)
  seed = (bar_index * 1_009) + (step_index * 313) + (base * 10_000).to_i
  rng  = Random.new(seed)
  gaussian = Math.sqrt(-2.0 * Math.log([rng.rand, 1e-9].max)) * Math.cos(2.0 * Math::PI * rng.rand)
  [[base * (1.0 + gaussian * spread), 0.03].max, 1.0].min.round(3)
end

def dilla_progression(mode = :donuts)
  names = DILLA_PROGRESSIONS.fetch(mode.to_sym, DILLA_PROGRESSIONS[:donuts])
  names.map { |n| PAD_CHORD_LOOKUP[n] || DONUT_CHORDS.find { |c| c[:name] == n } }.compact
end

def voice_lead_chords(chords)
  return chords if chords.length <= 1
  led = [chords.first]
  chords.each_cons(2) do |prev, nxt|
    prev_hz = prev[:hz]
    next_hz = nxt[:hz].map do |target|
      candidates = prev_hz.flat_map { |p| [p, p + 12, p - 12, target, target + 12, target - 12] }.uniq
      candidates.min_by { |c| (c - target).abs }
    end
    led << { name: nxt[:name], hz: next_hz.sort.uniq.first(5) }
  end
  led
end

def dilla_kick_pattern(bar, n_bars, feel)
  case feel
  when :get_dis_money
    [[7, 10, 14], [3, 7, 10, 12, 14], [6, 9, 13, 15], [2, 7, 10, 14]][(bar / 2) % 4]
  when :thelonious
    [[14, 3, 7, 10], [14, 3, 8, 11], [13, 2, 6, 10], [15, 3, 7, 11]][bar % 4]
  else
    pat = DILLA_KICK_PATTERNS[(bar / 4 + bar % 3) % DILLA_KICK_PATTERNS.length]
    pat = [0, 10] if bar.zero?
    pat = [0, 3, 6, 7, 10, 12, 14, 15] if bar == n_bars - 1
    pat
  end
end

def dilla_hat_steps(bar, feel)
  case feel
  when :get_dis_money
    (0..15).step(2).to_a + [3, 11]
  when :thelonious
    bar.even? ? [0, 2, 4, 6, 8, 10, 12, 14] : [1, 3, 5, 7, 9, 11, 13, 15]
  else
    bar % 8 == 7 ? [0, 4, 8, 12] : (0..15).step(2).to_a
  end.uniq.sort
end

def dilla_schedule(n_bars, beat_p, pad_chords, chord_bars: 4, phrase_bars: nil, drums_only: false,
                   swing: 58.0, feel: :default, timing: nil)
  bar_p  = (beat_p * 4.0).round(6)
  step_p = (beat_p / 4.0).round(6)
  events = Hash.new { |h, k| h[k] = [] }

  n_bars.times do |bar|
    base = bar * bar_p
    pattern = dilla_kick_pattern(bar, n_bars, feel)

    if feel == :thelonious
      pickup = base - step_p * 2
      events[:kick] << [[pickup + dilla_timing_ms(:kick_sync, bar, 0, timing) / 1000.0, 0.0].max.round(6), dilla_velocity(0.88, bar, 0)]
      events[:bass] << [[pickup + dilla_timing_ms(:bass, bar, 0, timing) / 1000.0, 0.0].max.round(6), dilla_velocity(0.50, bar, 0, spread: 0.05)]
    end

    pattern.each_with_index do |step, i|
      role = (feel == :get_dis_money || step.nonzero?) ? :kick_sync : :kick_anchor
      t = [base + step * step_p + dilla_swing_offset(step, step_p, swing) +
           dilla_timing_ms(role, bar, step, timing) / 1000.0, 0.0].max
      events[:kick] << [t.round(6), dilla_velocity(0.95, bar, step)]
      bass_skip = (feel == :get_dis_money && bar.zero? && step < 7) ||
                  (feel != :get_dis_money && bar.zero?)
      unless bass_skip
        bass_lag = feel == :get_dis_money ? step_p * 0.12 : 0.0
        events[:bass] << [[t + dilla_timing_ms(:bass, bar, step, timing) / 1000.0 + bass_lag, 0.0].max.round(6),
                          dilla_velocity(0.42, bar, step, spread: 0.06)]
      end
    end

    [4, 12].each do |step|
      t = [base + step * step_p + dilla_swing_offset(step, step_p, swing) +
           dilla_timing_ms(:snare, bar, step, timing) / 1000.0, 0.0].max
      events[:snare] << [t.round(6), dilla_velocity(0.60, bar, step)]
    end

    (bar.even? ? [3, 6, 11] : [6, 11, 15]).each do |step|
      t = [base + step * step_p + dilla_swing_offset(step, step_p, swing) +
           dilla_timing_ms(:ghost, bar, step, timing) / 1000.0, 0.0].max
      events[:ghost] << [t.round(6), dilla_velocity(0.28, bar, step, spread: 0.05)]
    end

    dilla_hat_steps(bar, feel).each_with_index do |step, i|
      role = [3, 11].include?(step) && feel == :get_dis_money ? :hat_up : (i.even? ? :hat_down : :hat_up)
      t = [base + step * step_p + dilla_swing_offset(step, step_p, swing) +
           dilla_timing_ms(role, bar, step, timing) / 1000.0, 0.0].max
      events[:hat] << [t.round(6), dilla_velocity(i.even? ? 0.48 : 0.38, bar, step, spread: 0.08)]
    end

    events[:open] << [[base + 6 * step_p + dilla_swing_offset(6, step_p, swing) + 0.008, 0.0].max.round(6),
                        dilla_velocity(0.28, bar, 6, spread: 0.04)] if [1, 3].include?(bar % 4)

    next if drums_only

    chord_change = phrase_bars ? (bar % chord_bars).zero? : (bar >= 1 && (bar % chord_bars).zero?)
    next unless chord_change

    chord = pad_chords[dilla_chord_index(bar, pad_chords, chord_bars: chord_bars, phrase_bars: phrase_bars)]
    pad_offset = case feel
                 when :get_dis_money then step_p * 2 + 0.012
                 when :thelonious then -step_p * 2
                 else 0.0
                 end
    pad_t = base + pad_offset + dilla_timing_ms(:pad, bar, 0, timing) / 1000.0
    sustain = ((phrase_bars || chord_bars) * bar_p * 0.92).round(4)
    events[:pad] << [[pad_t, 0.0].max.round(6), dilla_velocity(0.85, bar, 0, spread: 0.03), chord, sustain]
    chop_step = [1, 2, 5, 9, 13][bar % 5]
    chop_t = [base + chop_step * step_p + dilla_swing_offset(chop_step, step_p, swing), 0.0].max
    events[:chop] << [chop_t.round(6), dilla_velocity(0.55, bar, chop_step, spread: 0.04), chord]
  end
  events
end

def dilla_kick_wave(t, v, *)
  c = @dilla_cycle
  tm = (t % c).round(6)
  "between(mod(t,#{c}),#{tm},#{(tm + 0.42).round(6)})*#{v}*exp(-(mod(t,#{c})-#{tm})*7.4)*sin(2*PI*(45+115*exp(-20*(mod(t,#{c})-#{tm})))*(mod(t,#{c})-#{tm}))"
end

def dilla_bass_wave(t, v, root_hz = 43.0)
  c = @dilla_cycle
  tm = (t % c).round(6)
  lfo = "0.03*sin(2*PI*0.12*(mod(t,#{c})-#{tm}))"
  "between(mod(t,#{c}),#{tm},#{(tm + 0.46).round(6)})*#{v}*exp(-(mod(t,#{c})-#{tm})*3.2)*sin(2*PI*(#{root_hz}+#{root_hz}*#{lfo})*(mod(t,#{c})-#{tm}))"
end

def dilla_snare_env(events)
  c = @dilla_cycle
  hits = events.fetch(:snare, []).map { |t, v| [t, v, 0.18] } + events.fetch(:ghost, []).map { |t, v| [t, v, 0.09] }
  return "0" if hits.empty?
  hits.map do |t, v, d|
    tm = (t % c).round(6)
    "between(mod(t,#{c}),#{tm},#{(tm + d).round(6)})*#{v}*exp(-(mod(t,#{c})-#{tm})*#{(d < 0.12 ? 35 : 23).round(1)})"
  end.join("+")
end

def dilla_hat_env(events, key, decay: 78)
  c = @dilla_cycle
  dur = key == :open ? 0.25 : 0.06
  list = events.fetch(key, [])
  return "0" if list.empty?
  list.map do |t, v|
    tm = (t % c).round(6)
    "between(mod(t,#{c}),#{tm},#{(tm + dur).round(6)})*#{v}*exp(-(mod(t,#{c})-#{tm})*#{decay})"
  end.join("+")
end

def dilla_pad_layers(f, t, sustain, bar_i, gain: 0.035)
  drift = 1.0 + (Math.sin((bar_i + 1) * 1.7) * 0.0009)
  ff = (f * drift).round(4)
  layers = [
    "sin(2*PI*#{ff}*(t-#{t}))",
    "0.55*sin(2*PI*#{(ff * 1.004).round(4)}*(t-#{t}))",
    "0.32*sin(2*PI*#{(ff * 2.005).round(4)}*(t-#{t}))",
    "0.20*sin(2*PI*#{(ff * 0.5).round(4)}*(t-#{t}))"
  ].join("+")
  "between(t,#{t},#{(t + sustain).round(4)})*#{gain}*exp(-(t-#{t})*0.26)*(0.78+0.22*sin(2*PI*0.23*(t-#{t})))*(#{layers})"
end

def dilla_pad_wave(t, v, chord, sustain, bar_i = 0)
  voices = chord[:hz].each_with_index.map { |f, i| dilla_pad_layers(f, t, sustain, bar_i + i, gain: 0.028 + i * 0.003) }
  "(#{voices.join('+')})"
end

def dilla_drum_filter(snare_env, hat_env, open_env, duration, sample_input: nil)
  filter = []
  filter << "[0:a]aformat=channel_layouts=stereo[kick]"
  filter << "[1:a]aformat=channel_layouts=stereo,lowpass=f=140[bass]"
  filter << "[2:a]aformat=channel_layouts=stereo,asplit=3[ns][nh][no]"
  filter << "[ns]volume='(#{snare_env})':eval=frame,highpass=f=160,bandpass=f=1600:w=2600[snare]"
  filter << "[nh]volume='(#{hat_env})':eval=frame,highpass=f=6500[hats]"
  filter << "[no]volume='(#{open_env})':eval=frame,bandpass=f=5600:w=5200[open]"
  filter << "[4:a]aformat=channel_layouts=stereo,lowpass=f=2800,aphaser=speed=0.12:decay=0.35,adelay=9|13,aecho=0.18:0.22:120:0.22[pads]"
  filter << "[5:a]aformat=channel_layouts=stereo,highpass=f=120,lowpass=f=5000,aecho=0.18:0.22:90:0.28[chop]"
  labels  = %w[[kick] [bass] [snare] [hats] [open] [pads] [chop]]
  weights = %w[1.15 0.88 0.82 0.42 0.35 0.90 0.55]
  if sample_input
    filter << "[#{sample_input}:a]aformat=channel_layouts=stereo,atrim=0:#{duration},asetpts=PTS-STARTPTS," \
              "highpass=f=80,lowpass=f=14000,acrusher=bits=12:samples=2:mix=0.22[sample]"
    labels  << "[sample]"
    weights << "0.72"
  end
  filter << "[3:a]volume=0.14,highpass=f=90,lowpass=f=8000[vinyl]"
  sat = Math.tanh(1.55).round(6)
  filter << "#{labels.join}[vinyl]amix=inputs=#{labels.length + 1}:weights=#{weights.join(' ')} 0.22:duration=first," \
            "aeval=exprs='tanh(1.55*val(0))/#{sat}|tanh(1.55*val(1))/#{sat}'," \
            "acompressor=threshold=-22dB:ratio=2.8:attack=18:release=110:makeup=4," \
            "acrusher=bits=12:samples=1.69:mix=0.18," \
            "equalizer=f=45:width_type=o:width=1.2:g=2," \
            "alimiter=limit=0.93:level_out=0.95[out]"
  filter.join(";")
end

# --- Sample-based drum engine (MPC one-shots + Ruby mixer) ---

def drum_kit_ready?
  %w[kick.wav snare.wav ghost.wav hat.wav open_hat.wav bass_43.wav
     ind_kick.wav ind_clap.wav ind_hat.wav ind_bass_e.wav ind_bass_bb.wav ind_stab.wav].all? do |name|
    File.exist?(File.join(DRUM_DIR, name))
  end
end

def generate_drum_kit!
  abort "ffmpeg required" unless tool_available?("ffmpeg")
  FileUtils.mkdir_p(DRUM_DIR)
  sr = SAMPLE_RATE
  recipes = [
    ["kick.wav",
     ["-f", "lavfi", "-i", "aevalsrc='0.9*exp(-t*7.5)*sin(2*PI*(48+210*exp(-t*28))*t)+0.55*exp(-t*95)*sin(2*PI*3200*t)*between(t,0,0.006)':d=0.55:s=#{sr}"],
     "lowpass=f=180,acrusher=bits=12:samples=2:mix=0.42,equalizer=f=55:t=o:w=0.8:g=7,acompressor=threshold=-18dB:ratio=4:attack=2:release=40"],
    ["snare.wav",
     ["-f", "lavfi", "-i", "anoisesrc=d=0.32:color=white:amplitude=0.95", "-f", "lavfi", "-i", "sine=f=195:d=0.32"],
     "[0:a]asplit=2[n][n2];[n]highpass=f=1200,lowpass=f=7000,aeval=exprs='val(0)*exp(-t*32)'[crack];" \
     "[n2]bandpass=f=350:w=500,aeval=exprs='val(0)*exp(-t*18)'[rattle];[1:a]aeval=exprs='val(0)*exp(-t*22)'[body];" \
     "[crack][rattle][body]amix=inputs=3:weights=0.75 0.35 0.45,acrusher=bits=10:samples=2:mix=0.38"],
    ["ghost.wav",
     ["-f", "lavfi", "-i", "anoisesrc=d=0.14:color=pink:amplitude=0.7"],
     "highpass=f=900,lowpass=f=5500,aeval=exprs='val(0)*exp(-t*48)',volume=0.55"],
    ["hat.wav",
     ["-f", "lavfi", "-i", "anoisesrc=d=0.07:color=white:amplitude=1"],
     "highpass=f=7500,lowpass=f=15000,aeval=exprs='val(0)*exp(-t*140)',acrusher=bits=8:samples=1:mix=0.55"],
    ["open_hat.wav",
     ["-f", "lavfi", "-i", "anoisesrc=d=0.42:color=white:amplitude=0.85"],
     "highpass=f=6000,bandpass=f=9000:w=5000,aeval=exprs='val(0)*exp(-t*9)'"],
    ["bass_43.wav",
     ["-f", "lavfi", "-i", "aevalsrc='0.75*exp(-t*2.8)*sin(2*PI*(43+8*sin(2*PI*0.4*t))*t)':d=0.5:s=#{sr}"],
     "lowpass=f=120,equalizer=f=50:t=o:w=1:g=5"],
    ["ind_kick.wav",
     ["-f", "lavfi", "-i", "aevalsrc='0.95*exp(-t*5.5)*sin(2*PI*(50+520*exp(-t*45))*t)':d=0.65:s=#{sr}"],
     "aeval=exprs='tanh(5.5*val(0))/tanh(5.5)',lowpass=f=140,equalizer=f=52:t=o:w=0.6:g=9,acompressor=threshold=-16dB:ratio=10:attack=1:release=35"],
    ["ind_clap.wav",
     ["-f", "lavfi", "-i", "anoisesrc=d=0.22:color=white:amplitude=1"],
     "[0:a]asplit=3[a][b][c];[a]adelay=0|3,highpass=f=1400,aeval=exprs='val(0)*exp(-t*24)'[c1];" \
     "[b]adelay=12|15,highpass=f=1800,aeval=exprs='val(0)*exp(-(t-0.012)*30)'[c2];[c]bandpass=f=900:w=1800,aeval=exprs='val(0)*exp(-t*20)'[c3];" \
     "[c1][c2][c3]amix=inputs=3,acompressor=threshold=-14dB:ratio=6:attack=1:release=25"],
    ["ind_hat.wav",
     ["-f", "lavfi", "-i", "anoisesrc=d=0.05:color=white:amplitude=1"],
     "highpass=f=9000,aeval=exprs='val(0)*exp(-t*160)',equalizer=f=12000:t=o:w=2:g=4"],
    ["ind_bass_e.wav",
     ["-f", "lavfi", "-i", "aevalsrc='(2*mod(41.2*t,1)-1)*exp(-t*7)*0.8':d=0.24:s=#{sr}"],
     "lowpass=f=420,aeval=exprs='tanh(2.8*val(0))/tanh(2.8)'"],
    ["ind_bass_bb.wav",
     ["-f", "lavfi", "-i", "aevalsrc='(2*mod(58.27*t,1)-1)*exp(-t*7)*0.8':d=0.24:s=#{sr}"],
     "lowpass=f=420,aeval=exprs='tanh(2.8*val(0))/tanh(2.8)'"],
    ["ind_stab.wav",
     ["-f", "lavfi", "-i", "anoisesrc=d=0.35:color=white:amplitude=0.9", "-f", "lavfi", "-i", "sine=f=164.81:d=0.35"],
     "[0:a]bandpass=f=280:w=900,aeval=exprs='val(0)*exp(-t*14)'[m];[1:a]aeval=exprs='val(0)*exp(-t*11)'[t];" \
     "[m][t]amix=inputs=2:weights=0.7 0.35,lowpass=f=2800"]
  ]
  recipes.each do |name, inputs, chain|
    dest = File.join(DRUM_DIR, name)
    next if File.exist?(dest)
    if chain.include?("[") || chain.include?(";")
      sh! "ffmpeg", "-y", *inputs, "-filter_complex", chain, "-ar", SAMPLE_RATE.to_s, dest
    else
      sh! "ffmpeg", "-y", *inputs, "-af", chain, "-ar", SAMPLE_RATE.to_s, dest
    end
    puts "kit: #{name}"
  end
end

def ensure_drum_kit!
  generate_drum_kit! unless drum_kit_ready?
end

def load_mono_sample(path)
  pipe_floats(path, "aformat=channel_layouts=mono:sample_fmts=flt")
end

def write_stereo_wav(path, left, right)
  frames = [left.length, right.length].min
  pcm = (0...frames).flat_map { |i| [left[i], right[i]] }.pack("e*")
  stdin, stdout, stderr, wait = Open3.popen3(
    "ffmpeg", "-y", "-f", "f32le", "-ar", SAMPLE_RATE.to_s, "-ac", "2", "-i", "-",
    "-c:a", "pcm_s16le", path
  )
  stdin.write(pcm)
  stdin.close
  err = stderr.read
  abort "wav write failed: #{err}" unless wait.value.success?
  path
end

def mix_sample!(left, right, sample, frame, vel, pan = 0.0)
  sample.each_with_index do |s, i|
    idx = frame + i
    break if idx >= left.length
    v = s * vel
    left[idx]  += v * (0.5 - pan * 0.35)
    right[idx] += v * (0.5 + pan * 0.35)
  end
end

def render_sample_bus(events, duration, kit, mapping)
  frames = (duration * SAMPLE_RATE).ceil + SAMPLE_RATE
  left  = Array.new(frames, 0.0)
  right = Array.new(frames, 0.0)
  mapping.each do |event_key, default_key|
    events.fetch(event_key, []).each do |hit|
      t, v = hit[0], hit[1]
      sk = hit[2].is_a?(Symbol) ? hit[2] : default_key
      pan = hit[3] || 0.0
      mix_sample!(left, right, kit.fetch(sk), (t * SAMPLE_RATE).round, v, pan)
    end
  end
  peak = left.zip(right).flat_map { |l, r| [l.abs, r.abs] }.max || 1.0
  if peak > 0.98
    gain = 0.92 / peak
    left.map!  { |s| s * gain }
    right.map! { |s| s * gain }
  end
  [left, right]
end

def gate_expr(hits, hold: 0.38, scale: 1.0)
  parts = hits.map do |hit|
    t, v = hit[0], hit[1]
    "between(t,#{t.round(4)},#{(t + hold).round(4)})*#{(v * scale).round(4)}"
  end
  parts.empty? ? "0" : parts.join("+")
end

def pad_gate_expr(pad_events)
  parts = pad_events.map do |(t, v, _chord, sustain)|
    "between(t,#{t.round(4)},#{(t + sustain).round(4)})*#{(v * 0.85).round(4)}"
  end
  parts.empty? ? "0.22" : "(#{parts.join('+')})"
end

def dilla_stem_paths
  paths = {}
  paths[:mids]    = STEM_MIDS    if File.exist?(STEM_MIDS)
  paths[:highs]   = STEM_HIGHS   if File.exist?(STEM_HIGHS)
  paths[:sub]     = STEM_SUB     if File.exist?(STEM_SUB)
  paths[:center]  = STEM_CENTER  if File.exist?(STEM_CENTER)
  paths
end

# Full Jay Dee render: sample drums + stem chops, Dilla Time scheduling.
def render_dilla(destination = File.join(ROOT, "dilla_beat.mp3"), bars_count = nil)
  abort "ffmpeg required" unless tool_available?("ffmpeg")
  ensure_drum_kit!
  FileUtils.mkdir_p(File.dirname(destination))
  cfg      = dilla_resolve_config
  n_bars   = bars_count || bars
  beat_p   = 60.0 / cfg[:bpm]
  duration = (beat_p * 4.0 * n_bars).round(3)
  pads     = voice_lead_chords(dilla_progression(cfg[:progression]))
  events   = dilla_schedule(
    n_bars, beat_p, pads,
    chord_bars: cfg[:chord_bars], phrase_bars: cfg[:phrase_bars],
    swing: cfg[:swing], feel: cfg[:feel], timing: cfg[:timing]
  )

  kit = {
    kick: load_mono_sample(File.join(DRUM_DIR, "kick.wav")),
    snare: load_mono_sample(File.join(DRUM_DIR, "snare.wav")),
    ghost: load_mono_sample(File.join(DRUM_DIR, "ghost.wav")),
    hat: load_mono_sample(File.join(DRUM_DIR, "hat.wav")),
    open_hat: load_mono_sample(File.join(DRUM_DIR, "open_hat.wav")),
    bass_43: load_mono_sample(File.join(DRUM_DIR, "bass_43.wav"))
  }
  drum_tmp = File.join(ROOT, ".dilla_drums.wav")
  bass_hits = events[:bass].map { |t, v| [t, v, :bass_43] }
  left, right = render_sample_bus(
    events.merge(bass: bass_hits),
    duration,
    kit,
    kick: :kick, snare: :snare, ghost: :ghost, hat: :hat, open: :open_hat, bass: :bass_43
  )
  write_stereo_wav(drum_tmp, left, right)

  chop_gate = gate_expr(events[:chop], hold: 0.32, scale: 0.95)
  pad_gate  = pad_gate_expr(events[:pad])
  stems = dilla_stem_paths
  stem_tempo = (cfg[:bpm] / 90.0).round(4)
  pan_hz = (cfg[:bpm] / 15.0).round(3)

  command = ["ffmpeg", "-y", "-i", drum_tmp]
  idx = 1
  stem_map = {}
  stems.each do |key, path|
    command += ["-stream_loop", "-1", "-i", path]
    stem_map[key] = idx
    idx += 1
  end
  command += ["-f", "lavfi", "-i", "anoisesrc=color=pink:r=#{SAMPLE_RATE}:amplitude=0.035:d=#{duration}"]

  filt = ["[0:a]aformat=channel_layouts=stereo[drums]"]
  mix_labels = ["[drums]"]
  mix_weights = ["1.0"]

  if stem_map[:mids]
    pan_fx = cfg[:stereo_pan] ? ",apulsator=mode=sine:hz=#{pan_hz}:amount=0.38" : ""
    filt << "[#{stem_map[:mids]}:a]aformat=channel_layouts=stereo,atempo=#{stem_tempo},atrim=0:#{duration},asetpts=PTS-STARTPTS," \
             "lowpass=f=3400,volume='#{pad_gate}':eval=frame,aphaser=speed=0.11:decay=0.4#{pan_fx}[padbed]"
    mix_labels << "[padbed]"
    mix_weights << "0.82"
  end
  if stem_map[:highs]
    filt << "[#{stem_map[:highs]}:a]aformat=channel_layouts=stereo,atempo=#{stem_tempo},atrim=0:#{duration},asetpts=PTS-STARTPTS," \
             "highpass=f=400,volume='#{chop_gate}':eval=frame,aecho=0.35:0.4:90:0.25[chops]"
    mix_labels << "[chops]"
    mix_weights << "0.68"
  end
  if stem_map[:sub]
    filt << "[#{stem_map[:sub]}:a]aformat=channel_layouts=stereo,atempo=#{stem_tempo},atrim=0:#{duration},asetpts=PTS-STARTPTS," \
             "lowpass=f=160,volume=0.55[subbed]"
    mix_labels << "[subbed]"
    mix_weights << "0.72"
  end
  if stem_map[:center] && !stem_map[:mids]
    filt << "[#{stem_map[:center]}:a]aformat=channel_layouts=stereo,atrim=0:#{duration},asetpts=PTS-STARTPTS," \
             "lowpass=f=3000,volume='#{pad_gate}':eval=frame[padbed]"
    mix_labels << "[padbed]"
    mix_weights << "0.75"
  end

  filt << "[#{idx}:a]highpass=f=90,lowpass=f=8000,volume=0.18[vinyl]"
  mix_labels << "[vinyl]"
  mix_weights << "1.0"
  filt << "#{mix_labels.join}amix=inputs=#{mix_labels.length}:weights=#{mix_weights.join(' ')}:duration=first:normalize=0[mix]"
  filt.concat(sonitex_tape_filters("mix"))

  command += ["-filter_complex", filt.join(";"), "-map", "[out]", "-t", duration.to_s, *codec_for(destination), destination]
  sh!(*command)
  FileUtils.rm_f(drum_tmp)
  stem_note = stems.empty? ? "synth-only" : stems.keys.join("+")
  mix_note  = sonitex_enabled? ? "Sonitex STX-1269" : "dry"
  puts "wrote #{destination} (#{cfg[:bpm].to_i} BPM, #{n_bars} bars, #{cfg[:track]}, #{mix_note}, #{stem_note})"
end

def industrial_techno_section(bar)
  case bar
  when 0..7   then :intro
  when 8..31  then :groove
  when 32..39 then :breakdown
  when 40..47 then :build
  when 48..111 then :main
  when 112..119 then :peak
  else :outro
  end
end

# Arranged industrial techno: intro → groove → breakdown → build → main → peak → outro.
def industrial_techno_schedule(n_bars, beat_p)
  bar_p  = (beat_p * 4.0).round(6)
  step_p = (bar_p / 16.0).round(6)
  events = Hash.new { |h, k| h[k] = [] }

  n_bars.times do |bar|
    base    = bar * bar_p
    section = industrial_techno_section(bar)

    case section
    when :intro
      events[:kick] << [base, 0.82] if bar % 4 == 0
      events[:kick] << [base + step_p * 8, 0.55] if bar >= 4
    when :breakdown
      events[:kick] << [base, 0.65] if bar.even?
      events[:kick] << [base + step_p * 8, 0.45] if bar >= 36
    else
      [0, 4, 8, 12].each do |step|
        vel = section == :peak ? 1.0 : 0.9
        events[:kick] << [base + step * step_p, vel]
      end
      events[:kick] << [base + step_p * 14, 0.62] if section == :peak && bar.odd?
      events[:kick] << [base + step_p * 15, 0.48] if section == :build && bar >= 44
    end

    unless section == :intro && bar < 2
      clap_vel = section == :peak ? 0.78 : 0.62
      events[:clap] << [base + step_p * 4, clap_vel * 0.85] unless section == :breakdown && bar < 36
      events[:clap] << [base + step_p * 12, clap_vel]
      events[:clap] << [base + step_p * 14, 0.42] if section == :peak && bar % 2 == 1
    end

    hat_active = !(section == :breakdown && bar >= 34)
    16.times do |step|
      next unless hat_active
      seed = (bar * 97) + (step * 31)
      next if section == :groove && step.even? && seed % 9 == 0
      next if section == :main && step % 4 == 0 && seed % 11 == 0
      accent = step.odd? ? 1.08 : 1.0
      vel = (0.16 + (seed % 11) * 0.022) * accent
      vel *= 1.25 if section == :peak
      events[:hat] << [base + step * step_p, vel]
    end

    if hat_active && [1, 3, 5, 7].include?(bar % 8) && section != :intro
      events[:open] << [base + step_p * 6, section == :peak ? 0.42 : 0.32]
      events[:open] << [base + step_p * 14, 0.28] if section == :main || section == :peak
    end

    bass_active = section != :breakdown || bar < 35
    if bass_active
      acid_steps = section == :intro ? [0, 8] : [0, 2, 3, 5, 8, 10, 11, 14]
      acid_steps.each do |step|
        note = ((bar / 2 + step) % 4) >= 2 ? :ind_bass_bb : :ind_bass_e
        vel  = section == :peak ? 0.82 : 0.68
        vel *= 0.5 if section == :intro
        events[:bass] << [base + step * step_p, vel, note]
      end
    end

    if section != :breakdown && bar % 8 == 7
      events[:stab] << [base + step_p * 4, 0.52]
      events[:stab] << [base + step_p * 12, 0.38] if section == :peak
    end
  end
  events
end

def industrial_schedule(n_bars, beat_p)
  industrial_techno_schedule(n_bars, beat_p)
end

# Industrial techno: arranged 135 BPM groove, rumble sub, sidechain, dub space.
def render_industrial(destination = File.join(ROOT, "renders", "foundry_pulse.mp3"), bars_count = nil)
  abort "ffmpeg required" unless tool_available?("ffmpeg")
  ensure_drum_kit!
  FileUtils.mkdir_p(File.dirname(destination))
  ibpm     = ENV.fetch("IBPM", INDUSTRIAL_TECHNO_BPM.to_s).to_f
  beat_p   = (60.0 / ibpm).round(6)
  n_bars   = bars_count || (ENV["BARS"] ? bars : INDUSTRIAL_TECHNO_BARS)
  duration = (beat_p * 4.0 * n_bars).round(3)
  dotted_8th_ms = (3.0 * beat_p / 4.0 * 1000.0).round(1)
  events   = industrial_techno_schedule(n_bars, beat_p)

  kit = {
    ind_kick: load_mono_sample(File.join(DRUM_DIR, "ind_kick.wav")),
    ind_clap: load_mono_sample(File.join(DRUM_DIR, "ind_clap.wav")),
    ind_hat: load_mono_sample(File.join(DRUM_DIR, "ind_hat.wav")),
    open_hat: load_mono_sample(File.join(DRUM_DIR, "open_hat.wav")),
    ind_bass_e: load_mono_sample(File.join(DRUM_DIR, "ind_bass_e.wav")),
    ind_bass_bb: load_mono_sample(File.join(DRUM_DIR, "ind_bass_bb.wav")),
    ind_stab: load_mono_sample(File.join(DRUM_DIR, "ind_stab.wav"))
  }
  stab_hits = events[:stab].map { |t, v| [t, v, :ind_stab] }
  drum_tmp  = File.join(ROOT, ".ind_drums.wav")
  left, right = render_sample_bus(
    events.merge(stab: stab_hits),
    duration,
    kit,
    kick: :ind_kick, clap: :ind_clap, hat: :ind_hat, open: :open_hat, bass: :ind_bass_e, stab: :ind_stab
  )
  write_stereo_wav(drum_tmp, left, right)

  sides_path = File.join(STEM_DIR, "sides.mp3")
  command = ["ffmpeg", "-y", "-i", drum_tmp]
  idx = 1
  sides_idx = nil
  if File.exist?(sides_path)
    command += ["-stream_loop", "-1", "-i", sides_path]
    sides_idx = idx
    idx += 1
  end
  command += ["-f", "lavfi", "-i", "aevalsrc='0.55*sin(2*PI*38*t)*exp(-mod(t,#{beat_p})*1.8)':d=#{duration}:s=#{SAMPLE_RATE}"]
  rumble_idx = idx
  idx += 1
  command += ["-f", "lavfi", "-i", "anoisesrc=color=white:amplitude=0.045:d=#{duration}:r=#{SAMPLE_RATE}"]
  noise_idx = idx

  filt = []
  filt << "[0:a]aformat=channel_layouts=stereo,asplit=2[drums][drums_sc]"
  filt << "[#{rumble_idx}:a]aformat=channel_layouts=mono,lowpass=f=95,equalizer=f=48:t=o:w=0.8:g=8,volume=0.42[rumble]"
  if sides_idx
    filt << "[#{sides_idx}:a]aformat=channel_layouts=stereo,atrim=0:#{duration},asetpts=PTS-STARTPTS," \
            "highpass=f=180,lowpass=f=8500,volume=0.18[texture]"
  end
  filt << "[#{noise_idx}:a]highpass=f=300,lowpass=f=6000,volume=0.08[noise]"
  mix_in = ["[drums]", "[rumble]"]
  mix_w  = ["1.0", "0.55"]
  if sides_idx
    mix_in << "[texture]"
    mix_w << "0.28"
  end
  mix_in << "[noise]"
  mix_w << "0.12"
  filt << "#{mix_in.join}amix=inputs=#{mix_in.length}:weights=#{mix_w.join(' ')}:duration=first[bed]"
  filt << "[bed][drums_sc]sidechaincompress=threshold=-24dB:ratio=8:attack=0.5:release=110:level_sc=0.9[pumped]"
  filt << "[pumped]asplit=2[dry][rev_send]"
  filt << "[rev_send]highpass=f=100,lowpass=f=9000,aecho=0.7:0.8:480|960|1920|3200:0.6|0.45|0.3|0.18[verb]"
  filt << "[dry][verb]amix=inputs=2:weights=0.62 0.38[with_verb]"
  filt << "[with_verb]asplit=2[dry2][dly]"
  filt << "[dly]highpass=f=280,aecho=0.55:0.65:#{dotted_8th_ms}|#{(dotted_8th_ms * 2).round(1)}|#{(dotted_8th_ms * 3).round(1)}:0.75|0.55|0.35[echo]"
  filt << "[dry2][echo]amix=inputs=2:weights=0.7 0.3[pre]"
  sat = Math.tanh(3.8).round(6)
  filt << "[pre]extrastereo=m=1.18[wide]"
  filt << "[wide]aeval=exprs='tanh(3.8*val(0))/#{sat}|tanh(3.8*val(1))/#{sat}'[satd]"
  filt << "[satd]acompressor=threshold=-14dB:ratio=10:attack=1:release=45:makeup=3.5[comp]"
  filt << "[comp]equalizer=f=52:t=o:w=0.65:g=6,equalizer=f=120:t=o:w=1:g=2,equalizer=f=9500:t=o:w=2:g=-5[eq]"
  filt << "[eq]acrusher=bits=14:samples=2:mix=0.08,alimiter=limit=0.91:level_out=0.93[out]"

  command += ["-filter_complex", filt.join(";"), "-map", "[out]", "-t", duration.to_s, *codec_for(destination), destination]
  sh!(*command)
  FileUtils.rm_f(drum_tmp)
  puts "wrote #{destination} (#{ibpm.to_i} BPM industrial techno, #{n_bars} bars, #{duration}s)"
end

# =============================================================================
# HELP
# =============================================================================

def help
  puts <<~HELP
    Dilla Lab — unified audio engine (#{ROOT})

    SYNTHESIS
      dilla [out.mp3]              J Dilla beat — TRACK= preset (default donuts)
      hiphop [out.mp3]             Slum Village engine (default TRACK=get_dis_money)
      slum [dir]                   Batch session_01..14 → renders/ (Sonitex on)
      industrial [out.mp3]         Industrial techno (default renders/foundry_pulse.mp3)
      techno [out.mp3]             Hard distorted techno (#{TECHNO_BPM} BPM)
      analog [out.mp3]             Full analog pad restoration renderer
      analog_liveset [out] [min]   Long-form analog render
      render [out.mp3]             Core pad + drum synthesis
      electronium [out.mid]        Raymond Scott × Dilla MIDI (requires midilib)
      midi [out.mid]               Alias for electronium

    VOCAL MIXES (Sirkel Sag × Voicemails)
      mix | v11                    Latest mix recipe (default v11)
      v7 | v8 | v9 | v10           Earlier mix generations

    SAMPLE PIPELINE
      sample                       source → demucs → clean harmonic
      source [url|path] [out]      Capture audio
      separate [path]              Demucs stem separation
      demux <url|path> [deep]      6-stem demucs + optional EQ sub-bands
      clean <in> [out]             Denoise + loudnorm

    STEM RACK (stems/manifest.json)
      stems                        Register default rack from stems/
      stems add <name> <dir> [bpm] Add a stem set to manifest
      stems scan [root] [manifest] Legacy directory scan → manifest

    LIVESET
      liveset [set] [minutes]      Long-form WAV from stem rack (LIVESET_MIN=#{LIVESET_MIN})

    ANALYSIS & GRADE
      scan | ears | verify | study | grade | grade_list | chords

    ENV: BPM BARS TRACK PROGRESSION SWING SONITEX BEAT LIVESET_MIN LIVE_SECONDS
         SONITEX=1 (default) extreme tape mix | SONITEX=0 dry limiter only
         TRACK = internal preset id (use session_01..14 outputs via slum command)
         IBPM=135 BARS=128 for industrial techno length
  HELP
end

# =============================================================================
# ANALOG RENDERER (dilla_analog.rb)
# =============================================================================

def analog_two_bar_cycle
  (beat_seconds * 4 * 2).round(6)
end

def analog_drum_cycle_events(events)
  cycle = analog_two_bar_cycle
  events.map { |t, *rest| [(t % cycle).round(6), *rest] }
end

def kick_wave(t, v, cycle = analog_two_bar_cycle)
  tc = t.round(6)
  td = "mod(t,#{cycle})"
  "between(#{td},#{tc},#{(t + 0.42).round(6)})*#{v}*0.95*exp(-(#{td}-#{tc})*7.4)*" \
    "sin(2*PI*(45+115*exp(-20*(#{td}-#{tc})))*(#{td}-#{tc}))"
end

def bass_wave(t, v, f, cycle = analog_two_bar_cycle)
  tc = t.round(6)
  td = "mod(t,#{cycle})"
  "between(#{td},#{tc},#{(t + 0.46).round(6)})*#{v}*0.42*exp(-(#{td}-#{tc})*3.2)*sin(2*PI*#{f}*(#{td}-#{tc}))"
end

def analog_section_for_bar(b, total)
  return [:intro, 0.42] if b < 8
  return [:a, 1.00] if b < 24
  return [:a2, 1.00] if b < 40
  return [:break, 0.55] if b < 48
  return [:b, 1.00] if b < 64
  return [:drop, 0.72] if b < 72
  return [:c, 1.00] if b < 88
  [:outro, [0.25, 1.0 - ((b - 88) / [12.0, total - 88.0].max)].max]
end

def analog_rotate_chord(chord, bar_index)
  hz = chord[:hz].rotate((bar_index / 8) % chord[:hz].length)
  extra = case bar_index % 12
          when 0 then hz[0] * 1.067
          when 4 then hz[2] * 1.414
          when 8 then hz[3] * 1.122
          else nil
          end
  extra ? (hz + [extra]) : hz
end

def analog_schedule(bar_count)
  beat = beat_seconds
  bar_len = beat * 4
  step = bar_len / 16
  events = Hash.new { |h, k| h[k] = [] }
  kick_patterns = [[0, 7, 10, 14], [0, 5, 7, 10, 14], [0, 3, 7, 10, 12, 14], [0, 6, 9, 14]]

  bar_count.times do |b|
    sec, den = analog_section_for_bar(b, bar_count)
    base = b * bar_len
    kp = kick_patterns[(b / 8 + b % 3) % kick_patterns.length].dup
    kp = [0, 3, 6, 7, 10, 12, 14, 15] if b % 16 == 15
    kp = [0, 10] if sec == :intro && b > 2
    kp = [] if sec == :intro && b <= 2
    kp = (b.even? ? [0] : [0, 7]) if sec == :break
    kp = (b.even? ? [0, 10] : [0, 7, 14]) if sec == :drop
    kp = [0] if sec == :outro && b > bar_count - 8 && b % 4 == 0

    kp.each_with_index do |s, i|
      t = base + s * step + [0.000, 0.006, 0.011, -0.004, 0.018][(b + i) % 5]
      events[:kick] << [t, den]
      events[:bass] << [t + 0.023, den, ANALOG_ROOTS[(b / 4 + i) % ANALOG_ROOTS.length]] unless sec == :intro
    end

    [4, 12].each do |s|
      events[:snare] << [base + s * step + [-0.010, -0.006, 0.004, 0.010, 0.017][b % 5], den] unless sec == :intro
    end

    (b.even? ? [6, 11] : [3, 6, 11, 15]).each do |s|
      events[:ghost] << [base + s * step + [-0.014, 0.006, 0.018][(b + s) % 3], den * 0.32] unless [:intro, :drop].include?(sec)
    end

    hats = b % 16 == 7 ? [0, 4, 8, 12] : [0, 2, 4, 6, 8, 10, 12, 14]
    hats = b.even? ? [] : [0, 4, 8, 12] if sec == :break
    hats.each_with_index do |s, i|
      jitter = [-0.004, 0.000, 0.003, 0.006][(b + s) % 4]
      events[:hat] << [base + s * step + (i.odd? ? 0.018 : 0.002) + jitter, den * 0.52]
    end

    events[:open] << [base + 6 * step + 0.008, den * 0.30] if ![:intro, :break].include?(sec) && [1, 3].include?(b % 4)

    if b >= 2 && b % 4 == 0
      chord = analog_rotate_chord(PAD_CHORDS[(b / 4) % PAD_CHORDS.length], b)
      sustain = 3.2 + (b % 3) * 0.9
      events[:pad] << [base + 0.03, den, chord, sustain]
    end

    if b >= 2 && b % 2 == 0
      chord = analog_rotate_chord(PAD_CHORDS[(b / 4 + 3) % PAD_CHORDS.length], b)
      events[:chop] << [base + [1, 2, 5, 9, 13][b % 5] * step + [-0.022, 0.0, 0.017][b % 3], den, chord]
    end

    events[:riser] << [base + 2 * beat, 0.13] if [7, 23, 39, 47, 63, 71, 87].include?(b)
    events[:stop] << [base + 3 * beat, 0.18] if [23, 39, 47, 63, 71, 87].include?(b)
  end
  events
end

def analog_pad_expression(t, v, chord, sustain, bar_index)
  hz = chop_hz(chord)
  parts = hz.each_with_index.map do |f, i|
    drift = 1.0 + ((i - 2) * 0.0017) + (Math.sin((bar_index + i) * 1.7) * 0.0009)
    spike = (bar_index % 11 == i ? (ANALOG_CFG[:bad_tune_spike_cents] / 1200.0) : 0.0)
    ff = f * drift * (2.0 ** spike)
    [
      "sin(2*PI*#{ff}*(t-#{t}))",
      "0.55*sin(2*PI*#{ff * 1.004}*(t-#{t}))",
      "0.32*sin(2*PI*#{ff * 2.005}*(t-#{t}))",
      "0.20*sin(2*PI*#{ff * 0.5}*(t-#{t}))",
      "0.11*sin(2*PI*#{ff * 3.0}*(t-#{t}))"
    ].join("+")
  end.join("+")
  "between(t,#{t},#{t + sustain})*#{v}*0.035*exp(-(t-#{t})*0.26)*(0.78+0.22*sin(2*PI*0.23*(t-#{t})))*(#{parts})"
end

def render_analog(destination, bar_count: bars)
  abort "ffmpeg required" unless tool_available?("ffmpeg")
  dur = (bar_count * beat_seconds * 4).round(3)
  ev = analog_schedule(bar_count)
  cycle = analog_two_bar_cycle

  kick = analog_drum_cycle_events(ev[:kick]).map { |t, v| kick_wave(t, v, cycle) }
  bass = analog_drum_cycle_events(ev[:bass]).map { |t, v, f| bass_wave(t, v, f, cycle) }
  snare = ev[:snare].map { |t, v| "between(t,#{t},#{t + 0.18})*#{v}*0.60*exp(-(t-#{t})*23)" }
  ghost = ev[:ghost].map { |t, v| "between(t,#{t},#{t + 0.09})*#{v}*exp(-(t-#{t})*35)" }
  hat = ev[:hat].map { |t, v| "between(t,#{t},#{t + 0.06})*#{v}*exp(-(t-#{t})*78)" }
  open_hat = ev[:open].map { |t, v| "between(t,#{t},#{t + 0.25})*#{v}*exp(-(t-#{t})*11)" }
  pad = ev[:pad].each_with_index.map { |(t, v, chord, sustain), i| analog_pad_expression(t, v, chord, sustain, i) }
  chop = ev[:chop].map { |t, v, chord| chop_wave(chord, t, v) }
  risers = ev[:riser].map { |t, v| "between(t,#{t},#{t + 2.0})*#{v}*((t-#{t})/2.0)^2" }
  stops = ev[:stop].map { |t, v| "between(t,#{t},#{t + 1.1})*#{v}*exp(-(t-#{t})*2.2)" }

  inputs = [
    *lavfi("aevalsrc='#{expr_sum(kick)}':d=#{dur}:s=#{SAMPLE_RATE}"),
    *lavfi("aevalsrc='#{expr_sum(bass)}':d=#{dur}:s=#{SAMPLE_RATE}"),
    *lavfi("anoisesrc=color=white:r=#{SAMPLE_RATE}:amplitude=0.5:d=#{dur}"),
    *lavfi("anoisesrc=color=pink:r=#{SAMPLE_RATE}:amplitude=0.04:d=#{dur}"),
    *lavfi("aevalsrc='#{expr_sum(pad)}':d=#{dur}:s=#{SAMPLE_RATE}"),
    *lavfi("aevalsrc='#{expr_sum(chop)}':d=#{dur}:s=#{SAMPLE_RATE}"),
    *lavfi("aevalsrc='#{expr_sum(risers + stops)}':d=#{dur}:s=#{SAMPLE_RATE}")
  ]

  filter = <<~F
    [0:a]aformat=channel_layouts=stereo[k];
    [1:a]aformat=channel_layouts=stereo,lowpass=f=140[bs];
    [2:a]aformat=channel_layouts=stereo,asplit=3[ns][nh][no];
    [ns]volume='#{safe_volume_env(snare + ghost)}':eval=frame,highpass=f=160,bandpass=f=1600:w=2600[sn];
    [nh]volume='#{safe_volume_env(hat)}':eval=frame,highpass=f=6500[hh];
    [no]volume='#{safe_volume_env(open_hat)}':eval=frame,bandpass=f=5600:w=5200[op];
    [4:a]aformat=channel_layouts=stereo,lowpass=f=#{ANALOG_CFG[:lowpass_hz]},aphaser=speed=0.1:decay=0.35,adelay=#{ANALOG_CFG[:chorus_delay_l_ms]}|#{ANALOG_CFG[:chorus_delay_r_ms]},aecho=0.18:0.22:120:0.22[pad];
    [5:a]aformat=channel_layouts=stereo,highpass=f=120,lowpass=f=5000,aecho=0.18:0.22:90:0.28[chop];
    [6:a]aformat=channel_layouts=stereo,highpass=f=900,lowpass=f=9000[fx];
    [k][bs][sn][hh][op][pad][chop][fx]amix=inputs=8:weights=1.25 0.9 0.9 0.48 0.42 0.95 0.65 0.35:duration=longest[music];
    [3:a]volume=#{ANALOG_CFG[:vinyl_level]},highpass=f=90,lowpass=f=8000[vinyl];
    [music][vinyl]amix=inputs=2:weights=1 0.32:duration=first,
      acompressor=threshold=-18dB:ratio=3.5:attack=25:release=120:makeup=2,
      acrusher=bits=#{ANALOG_CFG[:sp_bits]}:samples=#{ANALOG_CFG[:sp_ratio].round(3)}:mix=0.22,
      aeval='(tanh((val(0)+#{ANALOG_CFG[:tape_dc]})*1.45)-0.072)/0.87|(tanh((val(1)+#{ANALOG_CFG[:tape_dc]})*1.45)-0.072)/0.87',
      highpass=f=30,lowpass=f=12000,equalizer=f=45:t=o:w=1.2:g=1,
      alimiter=level_out=0.96:limit=0.92[out]
  F

  FileUtils.mkdir_p(File.dirname(destination))
  sh! "ffmpeg", "-y", *inputs, "-filter_complex", filter.tr("\n", " "), "-map", "[out]", *codec_for(destination), destination
  puts "wrote #{destination}"
end

def analog_liveset(destination = File.join(ROOT, "analog_liveset.mp3"), minutes = 12)
  bar_count = [(minutes.to_f * 60.0 / (beat_seconds * 4)).ceil, 64].max
  render_analog(destination, bar_count: bar_count)
end

# =============================================================================
# HIP-HOP SYNTH (dilla_hiphop.rb)
# =============================================================================

# Batch-render tape presets — neutral session_XX filenames (no album track names).
def render_slum_album(output_dir = File.join(ROOT, "renders"))
  FileUtils.mkdir_p(output_dir)
  TAPE_RENDER_CATALOG.each do |entry|
    dest = File.join(output_dir, "#{entry[:out]}.mp3")
    prev = %w[TRACK BARS BPM PROGRESSION SWING SONITEX].each_with_object({}) { |k, h| h[k] = ENV[k] }
    ENV["TRACK"]   = entry[:preset].to_s
    ENV["BARS"]    = entry[:bars].to_s
    ENV["SONITEX"] = "1"
    render_dilla(dest, entry[:bars])
  ensure
    prev.each { |k, v| v ? ENV[k] = v : ENV.delete(k) }
  end
  puts "tape batch: #{TAPE_RENDER_CATALOG.length} sessions → #{output_dir}"
end

# Full-length MPC hip-hop: Slum Village Vol. 1/2 presets via TRACK= env.
def render_hiphop(destination = File.join(ROOT, "dilla_hiphop.mp3"))
  prev = %w[BPM BARS TRACK PROGRESSION SWING].each_with_object({}) { |k, h| h[k] = ENV[k] }
  ENV["TRACK"] ||= "get_dis_money"
  ENV["BARS"] ||= "63"
  render_dilla(destination, bars)
ensure
  prev.each { |k, v| v ? ENV[k] = v : ENV.delete(k) }
end

# =============================================================================
# TECHNO SYNTH (techno_hate.rb) — acid-industrial hybrid at 142 BPM
# =============================================================================

def render_techno(destination = File.join(ROOT, "techno_hate.mp3"))
  abort "ffmpeg required" unless tool_available?("ffmpeg")
  n_bars = [bars, TECHNO_BARS].max
  beat  = 60.0 / TECHNO_BPM
  bar   = beat * 4
  step  = beat / 4
  total = (bar * n_bars).round(3)

  kick_per_bar = Array.new(TECHNO_BARS) { [0, 4, 8, 12] }
  kick_per_bar[7] = [0, 4, 8, 12, 14, 15]
  clap_per_bar = Array.new(TECHNO_BARS) { [4, 12] }
  clap_per_bar[3] = [4, 12, 14]; clap_per_bar[7] = [4, 10, 12, 14]
  hat_per_bar  = Array.new(TECHNO_BARS) { [2, 6, 10, 14] }
  hat_per_bar[3] = []; hat_per_bar[5] = [0, 2, 4, 6, 8, 10, 12, 14]
  open_per_bar = Array.new(TECHNO_BARS) { [] }
  open_per_bar[3] = [14]; open_per_bar[7] = [14]
  acid_steps = [0, 3, 6, 8, 11, 14]
  bass_notes = [65.41, 65.41, 87.31, 65.41, 98.00, 98.00, 87.31, 65.41]

  cycle = (bar * TECHNO_BARS).round(6)
  kicks = TECHNO_BARS.times.flat_map { |b| kick_per_bar[b].map { |s| (b * bar + s * step).round(6) } }
  claps = TECHNO_BARS.times.flat_map { |b| clap_per_bar[b].map { |s| (b * bar + s * step).round(6) } }
  hats  = TECHNO_BARS.times.flat_map { |b| hat_per_bar[b].map  { |s| (b * bar + s * step).round(6) } }
  opens = TECHNO_BARS.times.flat_map { |b| open_per_bar[b].map { |s| (b * bar + s * step).round(6) } }
  acid_hits = TECHNO_BARS.times.flat_map { |b| bass_notes[b].then { |f| acid_steps.map { |s| [(b * bar + s * step).round(6), f] } } }

  kick_sig = kicks.map { |t|
    tm = (t % cycle).round(6)
    dt = "mod(t,#{cycle})-#{tm}"
    "between(mod(t,#{cycle}),#{tm},#{(tm + 0.18).round(6)})*0.95*exp(-#{dt}*8)*sin(2*PI*(110*#{dt}-250*#{dt}*#{dt}))"
  }
  acid_sig = acid_hits.map { |(t, f)|
    tm = (t % cycle).round(6)
    dt = "mod(t,#{cycle})-#{tm}"
    "between(mod(t,#{cycle}),#{tm},#{(tm + 0.14).round(6)})*0.6*exp(-#{dt}*9)*sin(2*PI*#{f}*#{dt})"
  }
  clap_env = claps.flat_map { |t|
    tm = (t % cycle).round(6)
    t1 = (tm + 0.012).round(6); t2 = (tm + 0.024).round(6)
    dt0 = "mod(t,#{cycle})-#{tm}"; dt1 = "mod(t,#{cycle})-#{t1}"; dt2 = "mod(t,#{cycle})-#{t2}"
    ["between(mod(t,#{cycle}),#{tm},#{(tm + 0.04).round(6)})*exp(-#{dt0}*40)",
     "between(mod(t,#{cycle}),#{t1},#{(t1 + 0.04).round(6)})*exp(-#{dt1}*50)",
     "between(mod(t,#{cycle}),#{t2},#{(t2 + 0.05).round(6)})*exp(-#{dt2}*30)"]
  }
  hat_env = hats.map  { |t| tm = (t % cycle).round(6); dt = "mod(t,#{cycle})-#{tm}"; "between(mod(t,#{cycle}),#{tm},#{(tm + 0.04).round(6)})*exp(-#{dt}*70)" }
  opn_env = opens.map { |t| tm = (t % cycle).round(6); dt = "mod(t,#{cycle})-#{tm}"; "between(mod(t,#{cycle}),#{tm},#{(tm + 0.5).round(6)})*exp(-#{dt}*10)" }

  filt = <<~F
    [0:a]aformat=channel_layouts=stereo,equalizer=f=55:t=o:w=0.7:g=4,
         aeval='tanh(val(0)*2.5)/tanh(2.5)|tanh(val(1)*2.5)/tanh(2.5)',
         acompressor=threshold=-10dB:ratio=6:attack=1:release=40:makeup=3[kick];
    [1:a]aformat=channel_layouts=stereo,
         aeval='tanh(val(0)*3.5)/tanh(3.5)|tanh(val(1)*3.5)/tanh(3.5)',
         equalizer=f=300:t=o:w=2:g=3,equalizer=f=1500:t=o:w=2:g=4,
         lowpass=f=4000[acid];
    [2:a]aformat=channel_layouts=stereo,asplit=3[nc][nh][no];
    [nc]volume='#{safe_volume_env(clap_env)}*0.6':eval=frame,bandpass=f=1500:w=2000,
        aecho=0.5:0.4:30|60:0.2|0.1[clap];
    [nh]volume='#{safe_volume_env(hat_env)}*0.4':eval=frame,highpass=f=8000[hat];
    [no]volume='#{safe_volume_env(opn_env)}*0.3':eval=frame,bandpass=f=7000:w=5000[open];
    [kick][acid][clap][hat][open]amix=inputs=5:weights=1.4 1.0 0.7 0.5 0.4:duration=longest[drums];
    [drums]highpass=f=30,acompressor=threshold=-14dB:ratio=8:attack=1:release=50:makeup=4[drums_comp];
    [drums_comp]aeval='tanh(val(0)*1.8)/tanh(1.8)|tanh(val(1)*1.8)/tanh(1.8)'[drums_sat];
    [drums_sat]equalizer=f=80:t=o:w=0.8:g=2,equalizer=f=8000:t=o:w=2:g=2[master_eq];
    [master_eq]alimiter=level_in=1.0:level_out=0.90:limit=0.85:attack=2:release=20[out]
  F

  FileUtils.mkdir_p(File.dirname(destination))
  sh! "ffmpeg", "-y",
      *lavfi("aevalsrc='#{expr_sum(kick_sig)}':d=#{total}:s=#{SAMPLE_RATE}"),
      *lavfi("aevalsrc='#{expr_sum(acid_sig)}':d=#{total}:s=#{SAMPLE_RATE}"),
      *lavfi("anoisesrc=color=white:r=#{SAMPLE_RATE}:amplitude=0.5:d=#{total}"),
      "-filter_complex", filt.tr("\n", " "), "-map", "[out]", "-b:a", "320k", destination
  puts "wrote #{destination}"
end

# =============================================================================
# VOCAL MIXES v7–v11 (make.rb)
# =============================================================================

def mix_out_path(ver)
  File.join(ROOT, "final_mix_#{ver}.mp3")
end

def mix_tmp(ver, name)
  "/tmp/#{ver}_#{name}.wav"
end

def mix_loop_beat
  ["-stream_loop", "-1", "-i", VOICEMAILS_BEAT, "-t", MIX_DUR.to_s]
end

def mix_beat_ms(bpm)
  (60_000 / bpm).to_i
end

def mix_dotted_8th(bpm)
  (mix_beat_ms(bpm) * 0.75).to_i
end

def mix_half(bpm)
  (mix_beat_ms(bpm) * 2).to_i
end

def mix_render(label, dest, inputs:, filter:, map:, args: ["-ar", "44100"])
  puts ">>> #{label}"
  sh! "ffmpeg", "-y", *inputs, "-filter_complex", filter.tr("\n", " "), "-map", map, *args, dest
end

def mix_v7
  ver = "v7"; d8 = mix_dotted_8th(MIX_BPM)
  beat_pre, vocals_pre, crackle = mix_tmp(ver, "beat"), mix_tmp(ver, "vocals"), mix_tmp(ver, "crackle")
  mix_render "beat: M/S + EQ + crunch + room", beat_pre, inputs: ["-i", VOICEMAILS_BEAT], map: "[beat_out]", filter: <<~F
    [0:a]aformat=sample_rates=44100:channel_layouts=stereo,volume=1.0[raw];
    [raw]pan=stereo|c0=c0+c1|c1=c0+c1[mid];
    [raw]pan=stereo|c0=c0-c1|c1=c1-c0[side];
    [mid]equalizer=f=60:t=o:w=0.8:g=7,equalizer=f=120:t=o:w=1:g=3,equalizer=f=400:t=o:w=1:g=-2,equalizer=f=2000:t=o:w=2:g=-3,
         acompressor=threshold=-20dB:ratio=6:attack=2:release=80:makeup=3[mid_eq];
    [side]equalizer=f=300:t=o:w=2:g=-4,equalizer=f=6000:t=o:w=3:g=4,acompressor=threshold=-18dB:ratio=3:attack=8:release=120:makeup=2[side_eq];
    [mid_eq][side_eq]amix=inputs=2:weights=1.4 0.6[beat_mix];
    [beat_mix]acrusher=level_in=1.2:level_out=0.9:bits=14:mode=log:aa=1[beat_crush];
    [beat_crush]aecho=0.6:0.4:30|60|90:0.15|0.08|0.04[beat_room];
    [beat_room]acompressor=threshold=-16dB:ratio=4:attack=3:release=60:makeup=2[beat_comp];
    [beat_comp]volume=0.88[beat_out]
  F
  mix_render "vocals: clear + shiny + precise", vocals_pre, inputs: ["-i", VOCALS[:processed]], map: "[voc_out]", filter: <<~F
    [0:a]aformat=sample_rates=44100:channel_layouts=stereo[vraw];
    [vraw]equalizer=f=180:t=o:w=1:g=-10,equalizer=f=300:t=o:w=1:g=-4,equalizer=f=900:t=o:w=1.5:g=2,
          equalizer=f=2500:t=o:w=2:g=5,equalizer=f=5000:t=o:w=2:g=4,equalizer=f=10000:t=o:w=3:g=5,equalizer=f=16000:t=o:w=3:g=4[voc_eq];
    [voc_eq]acompressor=threshold=-16dB:ratio=2.5:attack=5:release=80:makeup=5[voc_comp];
    [voc_comp]asplit=4[va][vb][vc][vd];
    [va]volume=1.0[voc_dry];
    [vb]aecho=0.7:0.6:350|700:0.3|0.12,equalizer=f=300:t=h:w=1:g=0[voc_plate];
    [vc]adelay=#{d8}|#{d8 * 2},equalizer=f=400:t=h:w=1:g=0[voc_ping];
    [vd]chorus=0.5:0.9:20|25:0.1|0.08:0.15|0.2:1.0|1.0[voc_shimmer];
    [voc_dry][voc_plate][voc_ping][voc_shimmer]amix=inputs=4:weights=1.4 0.4 0.35 0.5[voc_wet];
    [voc_wet]volume=1.35[voc_out]
  F
  mix_render "crackle", crackle, inputs: lavfi("anoisesrc=r=44100:color=pink:amplitude=0.025:d=300"), map: "[crack_out]", filter: <<~F
    [0:a]equalizer=f=3000:t=o:w=3:g=5,equalizer=f=80:t=o:w=1:g=-15,volume=0.18[crack_out]
  F
  mix_render "master v7", mix_out_path(ver), inputs: ["-i", beat_pre, "-i", vocals_pre, "-i", crackle], map: "[out]", args: ["-b:a", "320k"], filter: <<~F
    [0:a]volume=0.82[b];[1:a]volume=1.25[v];[2:a]volume=0.22[c];
    [b][v][c]amix=inputs=3:duration=first:weights=1 1.25 0.22[raw_mix];
    [raw_mix]acompressor=threshold=-22dB:ratio=3:attack=5:release=120:makeup=3[comp_low];
    [comp_low]acompressor=threshold=-12dB:ratio=5:attack=2:release=60:makeup=3[comp_mid];
    [comp_mid]acompressor=threshold=-6dB:ratio=10:attack=1:release=30:makeup=2[comp_hi];
    [comp_hi]equalizer=f=55:t=o:w=0.7:g=5,equalizer=f=160:t=o:w=1:g=2,equalizer=f=500:t=o:w=1.5:g=-2,equalizer=f=3000:t=o:w=2:g=-1,equalizer=f=10000:t=o:w=2:g=3[master_eq];
    [master_eq]aeval='tanh(val(0)*2.5)/tanh(2.5)|tanh(val(1)*2.5)/tanh(2.5)'[tape_sat];
    [tape_sat]aecho=0.3:0.2:18:0.06[air];
    [air]alimiter=level_in=1.0:level_out=0.98:limit=0.92:attack=3:release=25:level=disabled[limited];
    [limited]volume=0.96[out]
  F
end

def mix_v8
  ver = "v8"
  beat_pre, vocals_pre, crackle = mix_tmp(ver, "beat"), mix_tmp(ver, "vocals"), mix_tmp(ver, "crackle")
  mix_render "beat v8", beat_pre, inputs: mix_loop_beat, map: "[beat_out]", filter: <<~F
    [0:a]aformat=sample_rates=44100:channel_layouts=stereo[raw];
    [raw]equalizer=f=55:t=o:w=0.7:g=9,equalizer=f=120:t=o:w=1:g=4,equalizer=f=350:t=o:w=1.5:g=-6,equalizer=f=1000:t=o:w=2:g=-8,equalizer=f=4000:t=o:w=2:g=-5,equalizer=f=10000:t=o:w=3:g=-4[sub_heavy];
    [sub_heavy]acompressor=threshold=-18dB:ratio=8:attack=1:release=40:makeup=4[beat_comp];
    [beat_comp]tremolo=f=0.4:d=0.04[beat_wobble];
    [beat_wobble]acrusher=level_in=1.1:level_out=0.85:bits=16:mode=log:aa=1[beat_grit];
    [beat_grit]volume=0.75[beat_out]
  F
  mix_render "vocals v8", vocals_pre, inputs: ["-i", VOCALS[:precise]], map: "[voc_out]", filter: <<~F
    [0:a]aformat=sample_rates=44100:channel_layouts=stereo[vraw];
    [vraw]equalizer=f=200:t=o:w=1:g=-10,equalizer=f=1200:t=o:w=2:g=3,equalizer=f=3000:t=o:w=2:g=6,equalizer=f=6000:t=o:w=2:g=4,equalizer=f=12000:t=o:w=3:g=3[voc_eq];
    [voc_eq]acompressor=threshold=-18dB:ratio=4:attack=3:release=60:makeup=6[voc_comp];
    [voc_comp]asplit=2[vd][vr];[vd]volume=1.0[voc_dry];
    [vr]aecho=0.5:0.3:80|160:0.12|0.05[voc_tiny_room];
    [voc_dry][voc_tiny_room]amix=inputs=2:weights=1.0 0.3[voc_out]
  F
  mix_render "crackle v8", crackle, inputs: lavfi("anoisesrc=r=44100:color=pink:amplitude=0.05:d=#{MIX_DUR}"), map: "[crack_out]", filter: <<~F
    [0:a]equalizer=f=4000:t=o:w=3:g=8,equalizer=f=80:t=o:w=1:g=-20,volume=0.3[crack_out]
  F
  mix_render "master v8", mix_out_path(ver), inputs: ["-i", beat_pre, "-i", vocals_pre, "-i", crackle], map: "[out]", args: ["-b:a", "320k"], filter: <<~F
    [0:a]volume=0.85[b];[1:a]volume=1.4[v];[2:a]volume=0.35[c];
    [b][v][c]amix=inputs=3:duration=first:weights=1 1.4 0.35[mix];
    [mix]equalizer=f=60:t=o:w=0.8:g=3,equalizer=f=5000:t=o:w=2:g=2[master_eq];
    [master_eq]aeval='tanh(val(0)*1.8)/tanh(1.8)|tanh(val(1)*1.8)/tanh(1.8)'[tape];
    [tape]alimiter=level_in=1.0:level_out=0.97:limit=0.94:attack=5:release=80:level=disabled[out]
  F
end

def mix_v9
  ver = "v9"; slow = 0.92; bpm = MIX_BPM * slow; d8 = mix_dotted_8th(bpm); hf = mix_half(bpm)
  beat_pre, vocals_pre, pad, crackle = mix_tmp(ver, "beat"), mix_tmp(ver, "vocals"), mix_tmp(ver, "pad"), mix_tmp(ver, "crackle")
  mix_render "beat v9", beat_pre, inputs: mix_loop_beat, map: "[beat_out]", filter: <<~F
    [0:a]aformat=sample_rates=44100:channel_layouts=stereo[raw];
    [raw]asetrate=44100*0.7937,aresample=44100,atempo=#{slow}[pitched];
    [pitched]equalizer=f=50:t=o:w=0.7:g=9,equalizer=f=100:t=o:w=1:g=5,equalizer=f=600:t=o:w=2:g=-3,equalizer=f=3000:t=o:w=2:g=-5[beat_eq];
    [beat_eq]aphaser=in_gain=0.6:out_gain=0.8:delay=4:decay=0.5:speed=0.4:type=triangular[beat_phase];
    [beat_phase]aecho=0.7:0.5:200|400:0.3|0.15[beat_echo];
    [beat_echo]acompressor=threshold=-16dB:ratio=5:attack=4:release=80:makeup=3[beat_comp];
    [beat_comp]volume=0.78[beat_out]
  F
  mix_render "vocals v9", vocals_pre, inputs: ["-i", VOCALS[:precise]], map: "[voc_out]", filter: <<~F
    [0:a]aformat=sample_rates=44100:channel_layouts=stereo[vraw];
    [vraw]equalizer=f=150:t=o:w=1:g=-8,equalizer=f=800:t=o:w=2:g=2,equalizer=f=3000:t=o:w=2:g=3,equalizer=f=8000:t=o:w=3:g=5,equalizer=f=14000:t=o:w=3:g=4[voc_eq];
    [voc_eq]acompressor=threshold=-14dB:ratio=2.5:attack=8:release=200:makeup=5[voc_comp];
    [voc_comp]asplit=4[va][vb][vc][vd];[va]volume=0.9[voc_dry];
    [vb]aecho=0.88:0.92:800|1600|3200|6400:0.6|0.4|0.22|0.10[voc_cathedral];
    [vc]chorus=0.7:0.9:35|45|55:0.4|0.32|0.25:0.3|0.4|0.25:1.8|2.2|1.4[voc_shimmer];
    [vd]adelay=#{d8}|#{hf},acrusher=level_in=1.8:level_out=0.5:bits=6:mode=log:aa=1[voc_bit];
    [voc_dry][voc_cathedral][voc_shimmer][voc_bit]amix=inputs=4:weights=1 0.7 0.5 0.2[voc_wet];
    [voc_wet]aphaser=in_gain=0.5:out_gain=0.7:delay=3:decay=0.4:speed=0.2:type=sinusoidal[voc_phase];
    [voc_phase]flanger=delay=6:depth=5:speed=0.2:shape=sinusoidal[voc_flange];
    [voc_flange]volume=1.3[voc_out]
  F
  mix_render "pad v9", pad, inputs: lavfi("aevalsrc=0.12*sin(2*PI*138.59*t)+0.10*sin(2*PI*277.18*t)+0.08*sin(2*PI*349.23*t)+0.09*sin(2*PI*415.30*t)+0.05*sin(2*PI*554.37*t):s=44100:c=stereo:d=#{MIX_DUR}"), map: "[pad_out]", filter: <<~F
    [0:a]equalizer=f=800:t=o:w=2:g=-6,equalizer=f=3000:t=o:w=2:g=-10,aecho=0.9:0.85:600|1200:0.5|0.3[pad_echo];
    [pad_echo]chorus=0.6:0.8:40|50:0.3|0.25:0.4|0.3:1.5|2.0[pad_chorus];
    [pad_chorus]aphaser=in_gain=0.6:out_gain=0.8:delay=5:decay=0.6:speed=0.15:type=sinusoidal[pad_phase];
    [pad_phase]volume=0.22[pad_out]
  F
  mix_render "crackle v9", crackle, inputs: lavfi("anoisesrc=r=44100:color=pink:amplitude=0.02:d=#{MIX_DUR}"), map: "[crack_out]", filter: "[0:a]equalizer=f=5000:t=o:w=3:g=6,equalizer=f=80:t=o:w=1:g=-18,volume=0.12[crack_out]"
  mix_render "master v9", mix_out_path(ver), inputs: ["-i", beat_pre, "-i", vocals_pre, "-i", pad, "-i", crackle], map: "[out]", args: ["-b:a", "320k"], filter: <<~F
    [0:a]volume=0.80[b];[1:a]volume=1.20[v];[2:a]volume=0.25[p];[3:a]volume=0.15[c];
    [b][v][p][c]amix=inputs=4:duration=first:weights=1 1.2 0.25 0.15[mix];
    [mix]acompressor=threshold=-22dB:ratio=3:attack=8:release=200:makeup=3[comp1];
    [comp1]acompressor=threshold=-10dB:ratio=6:attack=2:release=60:makeup=2[comp2];
    [comp2]equalizer=f=50:t=o:w=0.7:g=4,equalizer=f=200:t=o:w=1:g=2,equalizer=f=2000:t=o:w=1.5:g=-2,equalizer=f=12000:t=o:w=2:g=3[master_eq];
    [master_eq]aeval='tanh(val(0)*3.0)/tanh(3.0)|tanh(val(1)*3.0)/tanh(3.0)'[tape];
    [tape]aecho=0.25:0.18:25:0.08[master_air];
    [master_air]alimiter=level_in=1.0:level_out=0.98:limit=0.93:attack=2:release=20:level=disabled[out]
  F
end

def mix_v10
  ver = "v10"; d8 = mix_dotted_8th(MIX_BPM)
  beat_pre, vocals_pre, pad, crackle = mix_tmp(ver, "beat"), mix_tmp(ver, "vocals"), mix_tmp(ver, "pad"), mix_tmp(ver, "crackle")
  mix_render "beat v10", beat_pre, inputs: mix_loop_beat, map: "[beat_out]", filter: <<~F
    [0:a]aformat=sample_rates=44100:channel_layouts=stereo[raw];
    [raw]equalizer=f=50:t=o:w=0.8:g=6,equalizer=f=100:t=o:w=1:g=4,equalizer=f=250:t=o:w=1:g=2,equalizer=f=700:t=o:w=1.5:g=-1,equalizer=f=3000:t=o:w=2:g=1,equalizer=f=8000:t=o:w=2:g=2,equalizer=f=14000:t=o:w=3:g=3[beat_eq];
    [beat_eq]acompressor=threshold=-22dB:ratio=3:attack=15:release=200:makeup=3[tape_comp];
    [tape_comp]aeval='#{HEDD}'[hedd];
    [hedd]aecho=0.5:0.3:25|50:0.1|0.05[spring];
    [spring]volume=0.82[beat_out]
  F
  mix_render "vocals v10", vocals_pre, inputs: ["-i", VOCALS[:precise]], map: "[voc_out]", filter: <<~F
    [0:a]aformat=sample_rates=44100:channel_layouts=stereo[vraw];
    [vraw]equalizer=f=160:t=o:w=1:g=-10,equalizer=f=350:t=o:w=1:g=-4,equalizer=f=1000:t=o:w=1.5:g=2,equalizer=f=2500:t=o:w=2:g=6,equalizer=f=5000:t=o:w=2:g=5,equalizer=f=10000:t=o:w=3:g=6,equalizer=f=16000:t=o:w=3:g=5[voc_eq];
    [voc_eq]acompressor=threshold=-16dB:ratio=2.5:attack=6:release=100:makeup=5[voc_comp];
    [voc_comp]aeval='#{HEDD}'[voc_hedd];
    [voc_hedd]asplit=3[va][vb][vc];[va]volume=1.0[vdry];
    [vb]adelay=#{d8}|#{d8},aecho=0.65:0.55:400|800:0.35|0.15[vplate];
    [vc]chorus=0.5:0.9:18|22:0.08|0.06:0.2|0.25:1.0|1.0[vdouble];
    [vdry][vplate][vdouble]amix=inputs=3:weights=1.4 0.45 0.35[voc_out]
  F
  mix_render "pad v10", pad, inputs: lavfi("aevalsrc=0.14*sin(2*PI*130.81*t)+0.11*sin(2*PI*261.63*t)+0.09*sin(2*PI*311.13*t)+0.10*sin(2*PI*392.00*t)+0.06*sin(2*PI*523.25*t):s=44100:c=stereo:d=#{MIX_DUR}"), map: "[pad_out]", filter: <<~F
    [0:a]equalizer=f=1000:t=o:w=2:g=-5,equalizer=f=4000:t=o:w=2:g=-10,equalizer=f=100:t=o:w=1:g=3[pad_eq];
    [pad_eq]aecho=0.85:0.8:500|1000:0.4|0.2[pad_echo];
    [pad_echo]chorus=0.5:0.8:35|45:0.25|0.2:0.35|0.25:1.2|1.6[pad_chorus];
    [pad_chorus]volume=0.18[pad_out]
  F
  mix_render "crackle v10", crackle, inputs: lavfi("anoisesrc=r=44100:color=pink:amplitude=0.015:d=#{MIX_DUR}"), map: "[crack_out]", filter: "[0:a]equalizer=f=4500:t=o:w=3:g=5,equalizer=f=80:t=o:w=1:g=-18,volume=0.10[crack_out]"
  mix_render "master v10", mix_out_path(ver), inputs: ["-i", beat_pre, "-i", vocals_pre, "-i", pad, "-i", crackle], map: "[out]", args: ["-b:a", "320k"], filter: <<~F
    [0:a]volume=0.84[b];[1:a]volume=1.22[v];[2:a]volume=0.20[p];[3:a]volume=0.12[c];
    [b][v][p][c]amix=inputs=4:duration=first:weights=1 1.22 0.20 0.12[mix];
    [mix]acompressor=threshold=-24dB:ratio=2:attack=20:release=300:makeup=2[glue];
    [glue]aeval='#{HEDD}'[bus_hedd];
    [bus_hedd]equalizer=f=45:t=o:w=0.7:g=3,equalizer=f=150:t=o:w=1:g=2,equalizer=f=700:t=o:w=1.5:g=-1,equalizer=f=12000:t=o:w=2:g=2[master_eq];
    [master_eq]aeval='tanh(val(0)*2.2)/tanh(2.2)|tanh(val(1)*2.2)/tanh(2.2)'[tape_sat];
    [tape_sat]aecho=0.2:0.15:15:0.05[air];
    [air]alimiter=level_in=1.0:level_out=0.98:limit=0.93:attack=4:release=40:level=disabled[out]
  F
end

def mix_v11
  ver = "v11"; d8 = mix_dotted_8th(MIX_BPM)
  beat_pre, vocals_pre, crackle = mix_tmp(ver, "beat"), mix_tmp(ver, "vocals"), mix_tmp(ver, "crackle")
  mix_render "beat v11", beat_pre, inputs: mix_loop_beat, map: "[beat_out]", filter: <<~F
    [0:a]aformat=sample_rates=44100:channel_layouts=stereo[raw];
    [raw]pan=stereo|c0=c0+c1|c1=c0+c1[mid];[raw]pan=stereo|c0=c0-c1|c1=c1-c0[side];
    [mid]lowpass=f=280[mid_bass];
    [mid_bass]equalizer=f=60:t=o:w=0.8:g=6,equalizer=f=120:t=o:w=1:g=3,acompressor=threshold=-18dB:ratio=6:attack=2:release=50:makeup=4[mid_punch];
    [side]equalizer=f=2000:t=o:w=0.8:g=-12,equalizer=f=2200:t=o:w=0.5:g=-8,lowpass=f=9000,equalizer=f=300:t=o:w=1:g=-3,equalizer=f=5000:t=o:w=2:g=2[side_clean];
    [side_clean]tremolo=f=0.35:d=0.05[side_wobble];
    [side_wobble]aphaser=in_gain=0.6:out_gain=0.8:delay=3:decay=0.4:speed=0.3:type=triangular[side_phase];
    [mid_punch][side_phase]amix=inputs=2:weights=1.3 0.7[beat_mix];
    [beat_mix]acompressor=threshold=-16dB:ratio=3:attack=5:release=100:makeup=2[beat_comp];
    [beat_comp]volume=0.82[beat_out]
  F
  mix_render "vocals v11", vocals_pre, inputs: ["-i", VOCALS[:original]], map: "[voc_out]", filter: <<~F
    [0:a]aformat=sample_rates=44100:channel_layouts=stereo[vraw];
    [vraw]equalizer=f=180:t=o:w=1:g=-8,equalizer=f=600:t=o:w=1.5:g=2,equalizer=f=2000:t=o:w=0.8:g=-6,equalizer=f=3000:t=o:w=2:g=5,equalizer=f=7000:t=o:w=2:g=4,equalizer=f=12000:t=o:w=3:g=2,lowpass=f=14000[voc_eq];
    [voc_eq]acompressor=threshold=-14dB:ratio=2.5:attack=8:release=150:makeup=5[voc_comp];
    [voc_comp]asplit=3[va][vb][vc];[va]volume=1.0[vdry];
    [vb]aecho=0.75:0.65:350|700:0.35|0.15[vplate];
    [vc]adelay=#{d8}|#{d8 * 2},chorus=0.5:0.8:20|25:0.08|0.06:0.2|0.25:1.0|1.0[vshine];
    [vdry][vplate][vshine]amix=inputs=3:weights=1.3 0.4 0.3[voc_wet];
    [voc_wet]aphaser=in_gain=0.5:out_gain=0.7:delay=2:decay=0.3:speed=0.25:type=sinusoidal[voc_phase];
    [voc_phase]volume=1.3[voc_out]
  F
  mix_render "crackle v11", crackle, inputs: lavfi("anoisesrc=r=44100:color=pink:amplitude=0.012:d=#{MIX_DUR}"), map: "[crack_out]", filter: "[0:a]equalizer=f=5000:t=o:w=3:g=4,equalizer=f=80:t=o:w=1:g=-18,volume=0.10[crack_out]"
  mix_render "master v11", mix_out_path(ver), inputs: ["-i", beat_pre, "-i", vocals_pre, "-i", crackle], map: "[out]", args: ["-b:a", "320k"], filter: <<~F
    [0:a]volume=0.85[b];[1:a]volume=1.25[v];[2:a]volume=0.12[c];
    [b][v][c]amix=inputs=3:duration=first:weights=1 1.25 0.12[mix];
    [mix]acompressor=threshold=-20dB:ratio=2.5:attack=18:release=250:makeup=3[glue];
    [glue]equalizer=f=55:t=o:w=0.8:g=4,equalizer=f=2000:t=o:w=0.6:g=-3,equalizer=f=8000:t=o:w=2:g=1,lowpass=f=16000[master_eq];
    [master_eq]aeval='tanh(val(0)*2.0)/tanh(2.0)|tanh(val(1)*2.0)/tanh(2.0)'[tape];
    [tape]aphaser=in_gain=0.3:out_gain=0.5:delay=2:decay=0.3:speed=0.15:type=sinusoidal[master_phase];
    [master_phase]alimiter=level_in=1.0:level_out=0.97:limit=0.93:attack=5:release=60:level=disabled[out]
  F
end

MIX_RECIPES = { "v7" => method(:mix_v7), "v8" => method(:mix_v8), "v9" => method(:mix_v9),
                "v10" => method(:mix_v10), "v11" => method(:mix_v11) }.freeze

def run_mix(ver = "v11")
  abort "unknown mix: #{ver}  have: #{MIX_RECIPES.keys.join(', ')}" unless MIX_RECIPES[ver]
  MIX_RECIPES[ver].call
  puts "done -> #{mix_out_path(ver)}"
  render_liveset(stems_load_manifest["active"] || "default", minutes: LIVESET_MIN) if File.exist?(STEM_MANIFEST)
end

# =============================================================================
# DEMUX (YouTube/path → demucs 6-stem)
# =============================================================================

def demux_fetch_audio(src)
  return File.expand_path(src) unless src.match?(%r{\Ahttps?://})
  FileUtils.mkdir_p(DEMUX_DIR)
  raw = File.join(DEMUX_DIR, "yt_#{Time.now.strftime("%Y%m%d_%H%M%S")}.wav")
  abort "yt-dlp required" unless tool_available?("yt-dlp")
  sh! "yt-dlp", "-x", "--audio-format", "wav", "-o", raw, src
  raw
end

def demux_six(src)
  audio = demux_fetch_audio(src)
  out = File.join(DEMUX_DIR, "demux")
  FileUtils.mkdir_p(out)
  abort "demucs required" unless tool_available?("demucs")
  sh! "demucs", "-n", DEMUX_MODEL, "-o", out, audio
  stem_dir = File.join(out, DEMUX_MODEL, File.basename(audio, ".*"))
  puts "stems -> #{stem_dir}"
  if Dir.exist?(stem_dir) && !stems_scan_set(stem_dir).empty?
    name = File.basename(audio, ".*").gsub(/[^A-Za-z0-9_-]/, "_")[0, 32]
    stems_register(name, stem_dir, source: src)
  end
  stem_dir
end

def demux_slice_band(src, dest, label, eq:)
  mix_render "band: #{label}", dest, inputs: ["-i", src], map: "[out]", filter: "[0:a]#{eq}[out]"
end

def demux_deep(src)
  stem_dir = demux_six(src)
  bands = File.join(stem_dir, "bands")
  FileUtils.mkdir_p(bands)
  bass = File.join(stem_dir, "bass.wav"); drums = File.join(stem_dir, "drums.wav")
  guitar = File.join(stem_dir, "guitar.wav"); piano = File.join(stem_dir, "piano.wav"); other = File.join(stem_dir, "other.wav")
  demux_slice_band bass,  File.join(bands, "sub_bass.wav"),    "sub_bass",    eq: "lowpass=f=60"
  demux_slice_band bass,  File.join(bands, "bass_mid.wav"),    "bass_mid",    eq: "highpass=f=60,lowpass=f=200"
  demux_slice_band drums, File.join(bands, "kick.wav"),        "kick",        eq: "lowpass=f=100"
  demux_slice_band drums, File.join(bands, "snare.wav"),       "snare",       eq: "highpass=f=200,lowpass=f=500"
  demux_slice_band drums, File.join(bands, "hats.wav"),        "hats",        eq: "highpass=f=5000"
  demux_slice_band other, File.join(bands, "mids.wav"),        "mids",        eq: "highpass=f=500,lowpass=f=2000"
  demux_slice_band other, File.join(bands, "highs_pluck.wav"), "highs_pluck", eq: "highpass=f=2000,lowpass=f=5000"
  demux_slice_band other, File.join(bands, "air.wav"),         "air",         eq: "highpass=f=5000"
  inst = File.join(bands, "instrumental.wav")
  mix_render "instrumental sum", inst, inputs: ["-i", bass, "-i", drums, "-i", guitar, "-i", piano, "-i", other],
    map: "[out]", filter: "[0:a][1:a][2:a][3:a][4:a]amix=inputs=5:duration=longest[out]"
  demux_slice_band inst, File.join(bands, "center.wav"), "center", eq: "pan=stereo|c0=c0+c1|c1=c0+c1"
  demux_slice_band inst, File.join(bands, "sides.wav"),  "sides",  eq: "pan=stereo|c0=c0-c1|c1=c1-c0"
  puts "bands -> #{bands}"
end

# =============================================================================
# LIVESET (long-form stem rack WAV)
# =============================================================================

def liveset_filter(count, periods: LIVESET_PERIODS)
  per_input = (0...count).map do |i|
    p = periods[i % periods.size]; phase = (i * 1.7).round(3); base = (0.55 + (i % 3) * 0.05).round(2)
    "[#{i}:a]aformat=sample_rates=44100:channel_layouts=stereo," \
      "volume='#{base}*(0.55+0.45*sin(2*PI*(t+#{phase})/#{p}))':eval=frame[s#{i}]"
  end
  taps = (0...count).map { |i| "[s#{i}]" }.join
  master = <<~F.tr("\n", " ").strip
    [mix]acompressor=threshold=-20dB:ratio=4:attack=30:release=300:makeup=2,
    highpass=f=30:width_type=q:width=1.2,equalizer=f=55:t=o:w=0.8:g=2,
    acrusher=bits=12:samples=1.69:level_in=1:level_out=1:mix=0.35,
    equalizer=f=2200:t=o:w=0.6:g=-2,
    aphaser=in_gain=0.4:out_gain=0.7:delay=2:decay=0.3:speed=0.12:type=sinusoidal,
    aeval='(tanh((val(0)+0.05)*1.6)-0.0798)/0.853|(tanh((val(1)+0.05)*1.6)-0.0798)/0.853',
    alimiter=level_in=1.0:level_out=0.95:limit=0.95:attack=5:release=80[out]
  F
  "#{per_input.join(';')};#{taps}amix=inputs=#{count}:weights=#{'1 ' * count}:duration=longest[mix];#{master}"
end

def render_liveset(name = "default", minutes: LIVESET_MIN)
  abort "ffmpeg required" unless tool_available?("ffmpeg")
  m = stems_load_manifest
  set = m["sets"][name] || m["sets"][m["active"]] or abort "liveset: no stem set '#{name}'"
  base_dir = File.join(STEM_DIR, set["dir"] || ".")
  files = set["files"]
  abort "liveset: empty set" if files.nil? || files.empty?
  inputs = files.flat_map { |f| ["-stream_loop", "-1", "-i", File.join(base_dir, f)] }
  out = File.join(ROOT, "liveset_#{name}_#{minutes}m.wav")
  sh! "ffmpeg", "-y", *inputs, "-filter_complex", liveset_filter(files.size),
      "-map", "[out]", "-t", (minutes * 60).to_s, "-ar", "44100", "-c:a", "pcm_s16le", out
  puts "liveset -> #{out}"
end

# =============================================================================
# ELECTRONIUM MIDI (electronium.rb) — lazy-loaded (requires midilib)
# =============================================================================

ELECTRONIUM_SOURCE = <<~'RUBY'
  module DillaElectronium
    PPQN = 480
    CHORDS = {
      fm9: [53, 56, 60, 63, 67], dbmaj9: [49, 53, 56, 60, 63], eb9: [51, 55, 58, 63, 65],
      bbm9: [46, 49, 53, 56, 60], cm7b5: [48, 51, 54, 58], c7alt: [48, 52, 58, 61, 63]
    }.freeze
    PROGRESSION = %i[fm9 dbmaj9 eb9 bbm9 cm7b5 fm9 c7alt fm9].freeze
    DRUMS = { kick: 36, snare: 38, closed_hat: 42, open_hat: 46 }.freeze
    F_MINOR = [65, 67, 68, 70, 72, 73, 75].freeze

    module Groove
      module_function
      def offset_ticks(type)
        case type
        when :kick then rand(-5..1)
        when :snare then rand(2..9)
        when :hat then rand(-3..4)
        when :bass then rand(-4..5)
        else rand(-5..5)
        end
      end
      def beat_to_ticks(beat, type = :melody)
        ((beat * PPQN) + offset_ticks(type)).round.clamp(0, 1 << 30)
      end
    end

    class TrackBuilder
      include MIDI
      def initialize(sequence, name, channel)
        @sequence = sequence
        @track = Track.new(sequence)
        @track.name = name
        @sequence.tracks << @track
        @channel = channel
      end
      def note(note, start_beat, duration_beats, velocity, feel: :melody)
        return if duration_beats <= 0
        start = Groove.beat_to_ticks(start_beat, feel)
        stop = [start + (duration_beats * PPQN).round, start + 1].max
        @track.events << NoteOn.new(@channel, note, velocity.clamp(1, 127), 0, start)
        @track.events << NoteOff.new(@channel, note, 0, 0, stop)
      end
      def finish
        @track.events.sort_by! { |e| [e.time_from_start, e.is_a?(NoteOff) ? 0 : 1] }
        @track.recalc_times
      end
    end

    class Composer
      include MIDI
      def initialize(bpm:, bars:)
        @bpm = bpm
        @bars = bars
        @sequence = Sequence.new
        @sequence.ppqn = PPQN
        add_tempo_track
      end
      def write(path)
        add_drums
        add_bass
        add_chords
        add_melody
        File.open(path, "wb") { |f| @sequence.write(f) }
        path
      end
      private
      def add_tempo_track
        track = Track.new(@sequence)
        @sequence.tracks << track
        track.events << Tempo.new(Tempo.bpm_to_mpq(@bpm))
        track.events << MetaEvent.new(META_SEQ_NAME, "Dilla Electronium")
        track.events << MetaEvent.new(META_TIME_SIG, [4, 2, 24, 8].pack("cccc"))
      end
      def add_drums
        drums = TrackBuilder.new(@sequence, "drums", 9)
        @bars.times do |bar|
          base = bar * 4.0
          [0.0, 1.75, 2.5, 3.5].each { |beat| drums.note(DRUMS[:kick], base + beat, 0.18, 105, feel: :kick) }
          [1.0, 3.0].each { |beat| drums.note(DRUMS[:snare], base + beat, 0.12, 92, feel: :snare) }
          drums.note(DRUMS[:snare], base + 2.75, 0.08, 42, feel: :snare) if bar.odd?
          8.times do |step|
            drums.note(DRUMS[:closed_hat], base + step * 0.5 + (step.odd? ? 0.055 : 0.0), 0.08, step.odd? ? 48 : 68, feel: :hat)
          end
          drums.note(DRUMS[:open_hat], base + 3.5, 0.18, 58, feel: :hat) if (bar % 4).zero?
        end
        drums.finish
      end
      def add_bass
        bass = TrackBuilder.new(@sequence, "bass", 0)
        chord_cycle.each_with_index do |chord_name, index|
          root = CHORDS.fetch(chord_name).first - 12
          start = index * 2.0
          bass.note(root, start, 0.62, 98, feel: :bass)
          bass.note(root + 12, start + 0.75, 0.25, 72, feel: :bass)
          bass.note(root, start + 1.5, 0.38, 86, feel: :bass)
        end
        bass.finish
      end
      def add_chords
        chords = TrackBuilder.new(@sequence, "electric-piano", 1)
        chord_cycle.each_with_index do |chord_name, index|
          CHORDS.fetch(chord_name).each_with_index do |note, voice|
            chords.note(note + 12, index * 2.0, 1.82, 48 + voice * 4, feel: :melody)
          end
        end
        chords.finish
      end
      def add_melody
        lead = TrackBuilder.new(@sequence, "lead-chops", 2)
        note_index = 2
        direction = 1
        (@bars * 4).times do |step|
          if rand < 0.78
            note = F_MINOR[note_index] + (rand < 0.25 ? 12 : 0)
            lead.note(note, step * 1.0, [0.25, 0.5, 0.75].sample, rand(62..88), feel: :melody)
          end
          note_index += direction * (rand < 0.2 ? 2 : 1)
          if note_index >= F_MINOR.length - 1
            note_index = F_MINOR.length - 2
            direction = -1
          elsif note_index <= 0
            note_index = 1
            direction = 1
          end
          direction *= -1 if rand < 0.18
        end
        lead.finish
      end
      def chord_cycle
        repeats = ((@bars * 4.0) / (PROGRESSION.length * 2.0)).ceil
        PROGRESSION.cycle.take(PROGRESSION.length * repeats)
      end
    end
  end
RUBY

def electronium_ensure_loaded!
  return if defined?(DillaElectronium::Composer)
  begin
    require "midilib"
    require "midilib/sequence"
    require "midilib/track"
    require "midilib/consts"
  rescue LoadError
    abort "midilib required — gem install midilib"
  end
  eval(ELECTRONIUM_SOURCE, TOPLEVEL_BINDING, __FILE__, __LINE__)
end

def electronium_generate(destination = File.join(ROOT, "dilla_electronium.mid"))
  electronium_ensure_loaded!
  path = DillaElectronium::Composer.new(bpm: bpm.to_i, bars: bars).write(destination)
  puts "wrote #{path}"
end

case ARGV.shift
when "help" then help
when "scan" then scan
when "sweep" then sweep
when "council" then council
when "debug" then debug
when "sample" then sample
when "source" then source(ARGV.shift, ARGV.shift)
when "livestream" then livestream(ARGV.shift, ARGV.shift)
when "separate" then separate(ARGV.shift)
when "render", nil then render(ARGV.shift || File.join(ROOT, "full_track.mp3"))
when "verify" then verify(ARGV.shift || File.join(ROOT, "full_track.mp3"))
when "chords" then chords
when "clean" then clean(ARGV.shift, ARGV.shift || File.join(ROOT, "clean.wav"))
when "stems" then stems(*ARGV)
when "study" then study(ARGV.shift, ARGV.shift)
when "rhythm" then rhythm(ARGV.shift)
when "melody" then melody(ARGV.shift)
when "harmony" then harmony(ARGV.shift)
when "semantics" then semantics(ARGV.shift)
when "ears"       then ears(ARGV.shift || File.join(ROOT, "full_track.mp3"))
when "play"       then play(ARGV.shift, (ARGV.shift || 8).to_i)
when "live"       then live((ARGV.shift || 32).to_i)
when "bass"       then bass((ARGV.shift || 55.0).to_f)
when "grade"      then grade(ARGV.shift, ARGV.shift, ARGV.shift)
when "grade_list" then grade_list
when "dilla"           then render_dilla(ARGV.shift || File.join(ROOT, "dilla_beat.mp3"))
when "hiphop"          then render_hiphop(ARGV.shift || File.join(ROOT, "dilla_hiphop.mp3"))
when "slum"            then render_slum_album(ARGV.shift || File.join(ROOT, "renders"))
when "industrial"      then render_industrial(ARGV.shift || File.join(ROOT, "renders", "foundry_pulse.mp3"))
when "techno"          then render_techno(ARGV.shift || File.join(ROOT, "techno_hate.mp3"))
when "analog"          then render_analog(ARGV.shift || File.join(ROOT, "analog_full.mp3"))
when "analog_liveset"  then analog_liveset(ARGV.shift || File.join(ROOT, "analog_liveset.mp3"), (ARGV.shift || 12).to_f)
when "electronium", "midi" then electronium_generate(ARGV.shift || File.join(ROOT, "dilla_electronium.mid"))
when "mix"  then run_mix(ARGV.shift || "v11")
when "v7"   then run_mix("v7")
when "v8"   then run_mix("v8")
when "v9"   then run_mix("v9")
when "v10"  then run_mix("v10")
when "v11"  then run_mix("v11")
when "demux"
  src = ARGV.shift or abort "usage: ruby dilla.rb demux <url-or-path> [deep]"
  ARGV[0] == "deep" ? demux_deep(src) : demux_six(src)
when "liveset"
  set = ARGV.shift || stems_load_manifest["active"] || "default"
  mins = (ARGV.shift || LIVESET_MIN).to_i
  render_liveset(set, minutes: mins)
else
  help
end
