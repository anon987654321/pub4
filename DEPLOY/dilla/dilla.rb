#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"

ROOT = File.expand_path(__dir__)
SAMPLE_DIR = File.join(ROOT, "samples")
STEM_DIR = File.join(ROOT, "stems")
SAMPLE_CLEAN = File.join(SAMPLE_DIR, "clean_harmonic.wav")
DEFAULT_BPM = 86.0
DEFAULT_BARS = 88
SAMPLE_RATE = 44_100
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
  { name: "Gmaj9", hz: [98.00, 123.47, 146.83, 185.00, 220.00] },
  { name: "Fmaj13", hz: [87.31, 110.00, 130.81, 164.81, 293.66] },
  { name: "Bbmaj9", hz: [116.54, 146.83, 174.61, 220.00, 261.63] },
  { name: "G13sus4", hz: [98.00, 130.81, 146.83, 174.61, 220.00] },
  { name: "Cm(maj9)", hz: [130.81, 155.56, 196.00, 246.94, 293.66] },
  { name: "C7#9 Hendrix", hz: [130.81, 164.81, 196.00, 233.08, 311.13] },
  { name: "Emaj9#11 Lydian", hz: [164.81, 207.65, 246.94, 369.99, 466.16] },
  { name: "Dm6/9", hz: [146.83, 174.61, 220.00, 246.94, 261.63] },
  { name: "Bbm6/9", hz: [116.54, 138.59, 174.61, 196.00, 261.63] },
  { name: "F#m11", hz: [92.50, 110.00, 138.59, 164.81, 246.94] },
  { name: "Abm9", hz: [103.83, 123.47, 155.56, 185.00, 233.08] },
  { name: "Ebmaj13", hz: [155.56, 196.00, 233.08, 293.66, 220.00] },
  { name: "E quartal", hz: [82.41, 110.00, 146.83, 196.00, 246.94] },
  { name: "A quartal", hz: [110.00, 146.83, 196.00, 261.63, 349.23] },
  { name: "D quartal", hz: [73.42, 98.00, 130.81, 174.61, 233.08] }
].freeze
COMMANDS = %w[scan sweep council debug sample source livestream separate render verify chords clean stems study rhythm melody harmony semantics ears play live bass grade grade_list dilla midi industrial batch_industrial batch_dilla neosoul modal gospel batch_neosoul batch_modal batch_gospel].freeze
JAZZ_CHORDS = [
  { name: "Dmaj9",     hz: [146.83, 185.00, 220.00, 277.18, 329.63] },
  { name: "Bm11",      hz: [123.47, 146.83, 185.00, 220.00, 329.63] },
  { name: "Gmaj9",     hz: [98.00,  123.47, 146.83, 185.00, 220.00] },
  { name: "Em11",      hz: [82.41,  98.00,  123.47, 146.83, 220.00] },
  { name: "Cmaj7#11",  hz: [130.81, 164.81, 196.00, 246.94, 369.99] },
  { name: "A13sus",    hz: [110.00, 146.83, 164.81, 196.00, 369.99] },
  { name: "F#7b9",     hz: [92.50,  116.54, 138.59, 164.81, 196.00] },
  { name: "Dmaj9",     hz: [146.83, 185.00, 220.00, 277.18, 329.63] },
].freeze

GOSPEL_CHORDS = [
  { name: "Fm9",        hz: [174.61, 207.65, 261.63, 311.13, 392.00] },
  { name: "Dbmaj7add9", hz: [138.59, 174.61, 207.65, 261.63, 311.13] },
  { name: "Eb7",        hz: [155.56, 196.00, 233.08, 277.18, 311.13] },
  { name: "Fm/C",       hz: [130.81, 174.61, 207.65, 261.63, 311.13] },
  { name: "Bbm7",       hz: [116.54, 138.59, 174.61, 207.65, 233.08] },
  { name: "C7alt",      hz: [130.81, 164.81, 196.00, 233.08, 311.13] },
  { name: "Abmaj7",     hz: [103.83, 130.81, 155.56, 196.00, 261.63] },
  { name: "Fm9",        hz: [174.61, 207.65, 261.63, 311.13, 392.00] },
].freeze

MODAL_CHORDS = [
  { name: "E quartal",  hz: [82.41,  110.00, 146.83, 196.00, 246.94] },
  { name: "A quartal",  hz: [110.00, 146.83, 196.00, 261.63, 349.23] },
  { name: "D quartal",  hz: [73.42,  98.00,  130.81, 174.61, 233.08] },
  { name: "Bb quartal", hz: [116.54, 155.56, 207.65, 277.18, 349.23] },
  { name: "F quartal",  hz: [87.31,  116.54, 155.56, 207.65, 261.63] },
  { name: "C quartal",  hz: [130.81, 174.61, 233.08, 311.13, 392.00] },
  { name: "G quartal",  hz: [98.00,  130.81, 174.61, 233.08, 311.13] },
  { name: "E quartal",  hz: [82.41,  110.00, 146.83, 196.00, 246.94] },
].freeze

DARK_CHORDS = [
  { name: "Cm9",   hz: [130.81, 155.56, 196.00, 233.08, 293.66] },
  { name: "Gb7#9", hz: [92.50,  116.54, 138.59, 164.81, 207.65] },
  { name: "Ebm9",  hz: [77.78,  92.50,  116.54, 138.59, 174.61] },
  { name: "A7#9",  hz: [110.00, 138.59, 164.81, 196.00, 311.13] },
  { name: "Abm9",  hz: [103.83, 123.47, 155.56, 185.00, 233.08] },
  { name: "D7#9",  hz: [146.83, 185.00, 220.00, 261.63, 311.13] },
  { name: "Dbm9",  hz: [69.30,  82.41,  103.83, 123.47, 155.56] },
  { name: "C7#9",  hz: [130.81, 164.81, 196.00, 233.08, 311.13] },
].freeze

DONUT_CHORDS = [
  { name: "Fm9",       hz: [174.61, 207.65, 261.63, 311.13, 392.00] },
  { name: "Dbmaj9",    hz: [138.59, 174.61, 207.65, 261.63, 311.13] },
  { name: "Bbm9",      hz: [116.54, 138.59, 174.61, 207.65, 261.63] },
  { name: "Eb7",       hz: [155.56, 196.00, 233.08, 277.18, 311.13] },
  { name: "Abmaj9low", hz: [103.83, 130.81, 155.56, 196.00, 233.08] },
  { name: "C7b9",      hz: [130.81, 138.59, 164.81, 196.00, 233.08] },
  { name: "Fm/C",      hz: [130.81, 174.61, 207.65, 261.63, 311.13] },
  { name: "Bb7sus",    hz: [116.54, 174.61, 196.00, 233.08, 311.13] },
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
}.freeze

# J Dilla drunk quantization: deliberate timing displacement from the grid.
# Each hit is offset by ±DRUNK_MAX_MS milliseconds of random swing — the
# characteristic feel of an MPC3000 played slightly loose on purpose.
DRUNK_MAX_MS = 22

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

def stems(root = File.join(ROOT, "samples/demucs"), manifest = File.join(ROOT, "samples/manifest.json"))
  sets = Dir.glob(File.join(root, "**", "*.{wav,mp3,flac,ogg,m4a}"), File::FNM_EXTGLOB).group_by { |path| File.dirname(path) }.map do |directory, files|
    { "name" => File.basename(directory), "bpm" => bpm, "stems" => stem_paths(files) }
  end
  FileUtils.mkdir_p(File.dirname(manifest))
  File.write(manifest, JSON.pretty_generate({ "version" => 6, "sets" => sets }) + "\n")
  puts "wrote #{manifest}"
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
  frames.each_cons(3).filter_map do |left, middle, right|
    next unless middle.last > threshold && middle.last > left.last && middle.last > right.last
    { time: middle.first.round(3), strength: middle.last.round(5), grid: (middle.first / hop_seconds).round }
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

def euclidean_rhythm(k, n)
  return Array.new(n, 0) if k <= 0
  return Array.new(n, 1) if k >= n

  ones  = Array.new(k) { [1] }
  zeros = Array.new(n - k) { [0] }

  loop do
    break if zeros.length <= 1
    count    = [ones.length, zeros.length].min
    new_ones = ones[0...count].zip(zeros[0...count]).map(&:flatten)
    leftover_ones  = ones[count..]
    leftover_zeros = zeros[count..]
    if leftover_ones.length >= leftover_zeros.length
      ones  = new_ones + leftover_ones
      zeros = leftover_zeros
    else
      ones  = new_ones
      zeros = leftover_ones + leftover_zeros
    end
    break if zeros.empty?
  end

  (ones + zeros).flatten
end

def euclidean_hat_expr(k, n, hat16_p, amplitude: 0.19)
  rhythm  = euclidean_rhythm(k, n)
  bar_p   = (hat16_p * 16.0).round(6)
  step_p  = (hat16_p * 16.0 / n).round(6)
  terms   = rhythm.each_with_index.map do |hit, i|
    next if hit != 1
    offset = (i * step_p).round(6)
    tm     = "mod(t-#{offset},#{bar_p})"
    "#{amplitude}*(random(3)-0.5)*lt(#{tm},0.013)*exp(-#{tm}*70)"
  end.compact
  terms.join("+")
end

def halftime_kick_expr(beat_p)
  bar_p = (beat_p * 4.0).round(6)
  tm    = "mod(t,#{bar_p})"
  "0.72*sin(2*PI*(46+88*exp(-#{tm}*18))*#{tm})*exp(-#{tm}*8)"
end

def polyrhythm_kick_expr(beat_p)
  bar_p  = (beat_p * 4.0).round(6)
  step_p = (beat_p / 4.0).round(6)
  rhythm = euclidean_rhythm(5, 16)
  terms  = rhythm.each_with_index.map do |hit, i|
    next if hit != 1
    offset = (i * step_p).round(6)
    tm     = "mod(t-#{offset},#{bar_p})"
    "0.52*sin(2*PI*(46+88*exp(-#{tm}*20))*#{tm})*exp(-#{tm}*10)"
  end.compact
  terms.join("+")
end

# --- J Dilla style beat engine ---

def dilla_timing_ms(role, bar_index, step_index)
  range = DILLA_TIMING_MS.fetch(role)
  span  = range.end - range.begin
  seed  = (bar_index * 97) + (step_index * 31) + role.hash.abs
  range.begin + (seed % (span + 1))
end

def dilla_progression(mode = :soul)
  names = DILLA_PROGRESSIONS.fetch(mode.to_sym, DILLA_PROGRESSIONS[:soul])
  names.map { |name| PAD_CHORD_LOOKUP.fetch(name) }
end

def dilla_swing_offset(step_index, step_p, swing)
  return 0.0 if swing.to_f <= 0.0
  return 0.0 if step_index.even?

  swing_ratio = swing.to_f.clamp(0.0, 100.0) / 100.0
  (step_p * swing_ratio * 0.5).round(6)
end

def dilla_velocity(base, bar_index, step_index, spread: 0.10)
  seed = (bar_index * 1_009) + (step_index * 313) + (base * 10_000).to_i
  rng  = Random.new(seed)
  u1   = [rng.rand, 1e-9].max
  u2   = rng.rand
  gaussian = Math.sqrt(-2.0 * Math.log(u1)) * Math.cos(2.0 * Math::PI * u2)
  [[base * (1.0 + (gaussian * spread)), 0.03].max, 1.0].min.round(3)
end

def dilla_poly_steps(mode)
  case mode.to_s
  when "3" then [0, 5, 10]
  when "5" then [0, 3, 6, 10, 13]
  else nil
  end
end

def pressure_drone_expr(t, v, root_hz = 38.0)
  drift = 1.0 + (0.014 * Math.sin(t * 0.19))
  "between(t,#{t},#{(t + 16.0).round(6)})*#{v}*0.18*exp(-(t-#{t})*0.11)*(sin(2*PI*#{(root_hz * drift).round(4)}*(t-#{t}))+0.42*sin(2*PI*#{(root_hz * 0.5).round(4)}*(t-#{t})))"
end

def loop_metadata_path(destination)
  "#{destination}.loop.json"
end

def write_loop_metadata(destination, beat_p, n_bars, duration)
  data = {
    source: File.basename(destination),
    bpm: bpm.round(3),
    beat_seconds: beat_p.round(6),
    bars: n_bars,
    duration_seconds: duration.round(3),
    loop_start: 0.0,
    loop_end: duration.round(3),
    acid_compatible: true
  }
  File.write(loop_metadata_path(destination), JSON.pretty_generate(data) + "\n")
end

def loop_metadata_args(duration)
  [
    "-metadata", "loop_start=0",
    "-metadata", "loop_end=#{(duration * SAMPLE_RATE).to_i}",
    "-metadata", "ACID_LOOP=1"
  ]
end

def dilla_schedule(n_bars, beat_p, pad_chords, chord_bars: 4, drums_only: false, swing: 58.0, pressure: false, polyrhythm: nil)
  bar_p  = (beat_p * 4.0).round(6)
  step_p = (beat_p / 4.0).round(6)
  events = Hash.new { |h, k| h[k] = [] }
  poly_steps = dilla_poly_steps(polyrhythm)

  n_bars.times do |bar|
    base = bar * bar_p
    pattern = DILLA_KICK_PATTERNS[(bar / 4 + bar % 3) % DILLA_KICK_PATTERNS.length]
    pattern = poly_steps if poly_steps && (bar % 2).zero?
    pattern = [0, 10] if bar.zero?
    pattern = [0, 3, 6, 7, 10, 12, 14, 15] if bar == n_bars - 1

    pattern.each_with_index do |step, i|
      role = step.zero? ? :kick_anchor : :kick_sync
      t = [base + (step * step_p) + dilla_swing_offset(step, step_p, swing) + (dilla_timing_ms(role, bar, step) / 1000.0), 0.0].max
      events[:kick] << [t.round(6), dilla_velocity(0.95, bar, step)]
      events[:bass] << [[t + dilla_timing_ms(:bass, bar, step) / 1000.0, 0.0].max.round(6), dilla_velocity(0.42, bar, step, spread: 0.06)] unless bar.zero?
    end

    [4, 12].each do |step|
      t = [base + (step * step_p) + dilla_swing_offset(step, step_p, swing) + (dilla_timing_ms(:snare, bar, step) / 1000.0), 0.0].max
      events[:snare] << [t.round(6), dilla_velocity(0.60, bar, step)]
    end

    ghost_steps = bar.even? ? [3, 6, 11] : [6, 11, 15]
    ghost_steps.each do |step|
      t = [base + (step * step_p) + dilla_swing_offset(step, step_p, swing) + (dilla_timing_ms(:ghost, bar, step) / 1000.0), 0.0].max
      events[:ghost] << [t.round(6), dilla_velocity(0.28, bar, step, spread: 0.05)]
    end

    hat_steps = bar % 8 == 7 ? [0, 4, 8, 12] : (0..15).step(2).to_a
    hat_steps.each_with_index do |step, i|
      role = i.even? ? :hat_down : :hat_up
      t = [base + (step * step_p) + dilla_swing_offset(step, step_p, swing) + (dilla_timing_ms(role, bar, step) / 1000.0), 0.0].max
      events[:hat] << [t.round(6), dilla_velocity(i.even? ? 0.48 : 0.38, bar, step, spread: 0.08)]
    end

    open_step = 6
    events[:open] << [[base + (open_step * step_p) + dilla_swing_offset(open_step, step_p, swing) + 0.008, 0.0].max.round(6), dilla_velocity(0.28, bar, open_step, spread: 0.04)] if [1, 3].include?(bar % 4)

    unless drums_only
      if bar >= 1 && (bar % chord_bars).zero?
        chord = pad_chords[(bar / chord_bars) % pad_chords.length]
        pad_t = base + (dilla_timing_ms(:pad, bar, 0) / 1000.0)
        sustain = (chord_bars * bar_p * 0.92).round(4)
        events[:pad] << [pad_t.round(6), dilla_velocity(0.85, bar, 0, spread: 0.03), chord, sustain]
        chop_step = [1, 2, 5, 9, 13][bar % 5]
        chop_t = [base + (chop_step * step_p) + dilla_swing_offset(chop_step, step_p, swing), 0.0].max
        events[:chop] << [chop_t.round(6), dilla_velocity(0.55, bar, chop_step, spread: 0.04), chord]
      end
    end

    if pressure
      pressure_step = [0, 8][bar % 2]
      pressure_t = [base + (pressure_step * step_p), 0.0].max
      events[:pressure] << [pressure_t.round(6), dilla_velocity(0.18, bar, pressure_step, spread: 0.02), 38.0 + ((bar % 4) * 0.5)]
    end
  end
  events
end

def event_expr(events, key, &waveform)
  events.fetch(key).map { |t, v, *rest| waveform.call(t, v, *rest) }.join("+")
end

def kick_wave(t, v, *)
  c = @dilla_cycle
  tm = (t % c).round(6)
  "between(mod(t,#{c}),#{tm},#{(tm + 0.42).round(6)})*#{v}*exp(-(mod(t,#{c})-#{tm})*7.4)*sin(2*PI*(45+115*exp(-20*(mod(t,#{c})-#{tm})))*(mod(t,#{c})-#{tm}))"
end

def bass_wave(t, v, root_hz = 43.0)
  c = @dilla_cycle
  tm = (t % c).round(6)
  lfo = "0.03*sin(2*PI*0.12*(mod(t,#{c})-#{tm}))"
  "between(mod(t,#{c}),#{tm},#{(tm + 0.46).round(6)})*#{v}*exp(-(mod(t,#{c})-#{tm})*3.2)*sin(2*PI*(#{root_hz}+#{root_hz}*#{lfo})*(mod(t,#{c})-#{tm}))"
end

def snare_env(events)
  c = @dilla_cycle
  hits = events[:snare].map { |t, v| [t, v, 0.18] } + events[:ghost].map { |t, v| [t, v, 0.09] }
  hits.map do |t, v, d|
    tm = (t % c).round(6)
    "between(mod(t,#{c}),#{tm},#{(tm + d).round(6)})*#{v}*exp(-(mod(t,#{c})-#{tm})*#{(d < 0.12 ? 35 : 23).round(1)})"
  end.join("+")
end

def hat_env(events, key, decay: 78)
  c = @dilla_cycle
  dur = key == :open ? 0.25 : 0.06
  events.fetch(key).map do |t, v|
    tm = (t % c).round(6)
    "between(mod(t,#{c}),#{tm},#{(tm + dur).round(6)})*#{v}*exp(-(mod(t,#{c})-#{tm})*#{decay})"
  end.join("+")
end

def pad_voice_layers(f, t, sustain, bar_i, gain: 0.035)
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

def pad_wave(t, v, chord, sustain, bar_i = 0)
  voices = chord[:hz].each_with_index.map { |f, i| pad_voice_layers(f, t, sustain, bar_i + i, gain: 0.028 + i * 0.003) }
  "(#{voices.join('+')})"
end

def chop_wave(t, v, chord)
  f = chord[:hz][(t * 10).to_i % chord[:hz].length]
  "between(t,#{t},#{(t + 0.55).round(6)})*#{v}*0.11*exp(-(t-#{t})*1.7)*(sin(2*PI*#{f}*(t-#{t}))+0.35*sin(2*PI*#{(f * 1.5).round(4)}*(t-#{t})))"
end

def pressure_wave(t, v, root_hz = 38.0)
  pressure_drone_expr(t, v, root_hz)
end

def voice_lead_chords(chords)
  return chords if chords.length <= 1
  led = [chords.first]
  chords.each_cons(2) do |prev, nxt|
    prev_hz = prev[:hz]
    next_hz = nxt[:hz].map do |target|
      candidates = prev_hz.map { |p| [p, p + 12, p - 12, target, target + 12, target - 12] }.flatten.uniq
      candidates.min_by { |c| (c - target).abs }
    end
    led << { name: nxt[:name], hz: next_hz.sort.uniq.first(5) }
  end
  led
end

def dilla_drum_filter(snare_env, hat_env, open_env, pad_expr, chop_expr, duration, sample_input: nil, pressure_input: nil)
  pad_idx = 4
  chop_idx = 5
  filter = []
  filter << "[0:a]aformat=channel_layouts=stereo[kick]"
  filter << "[1:a]aformat=channel_layouts=stereo,lowpass=f=140[bass]"
  filter << "[2:a]aformat=channel_layouts=stereo,asplit=3[ns][nh][no]"
  filter << "[ns]volume='(#{snare_env})':eval=frame,highpass=f=160,bandpass=f=1600:w=2600[snare]"
  filter << "[nh]volume='(#{hat_env})':eval=frame,highpass=f=6500[hats]"
  filter << "[no]volume='(#{open_env})':eval=frame,bandpass=f=5600:w=5200[open]"
  filter << "[#{pad_idx}:a]aformat=channel_layouts=stereo,lowpass=f=2800,aphaser=speed=0.12:decay=0.35,adelay=9|13,aecho=0.18:0.22:120:0.22[pads]"
  filter << "[#{chop_idx}:a]aformat=channel_layouts=stereo,highpass=f=120,lowpass=f=5000,aecho=0.18:0.22:90:0.28[chop]"
  labels  = %w[[kick] [bass] [snare] [hats] [open] [pads] [chop]]
  weights = %w[1.15 0.88 0.82 0.42 0.35 0.90 0.55]
  if sample_input
    filter << "[#{sample_input}:a]aformat=channel_layouts=stereo,atrim=0:#{duration},asetpts=PTS-STARTPTS," \
              "highpass=f=80,lowpass=f=14000,acrusher=bits=12:samples=2:mix=0.22[sample]"
    labels  << "[sample]"
    weights << "0.72"
  end
  if pressure_input
    filter << "[#{pressure_input}:a]aformat=channel_layouts=stereo,lowpass=f=160,highpass=f=28,volume=0.20,acompressor=threshold=-24dB:ratio=3:attack=30:release=220[pressure]"
    labels  << "[pressure]"
    weights << "0.28"
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

# Drunk quantization: return an array of per-beat timing offsets in seconds.
# Dilla's signature feel — hits land slightly before or after the grid,
# never random but never locked, like a human with perfect rhythm who chose not to use it.
def drunk_offsets(n)
  n.times.map { (rand * 2 - 1) * DRUNK_MAX_MS / 1000.0 }
end

# Build kick expression with drunk timing: each kick is offset from the grid.
def dilla_kick_expr(duration, drunk)
  beat_p = beat_seconds * 2.0
  # Kicks on beats 1 and 3, offset by drunk timing
  kicks  = drunk.each_slice(4).flat_map do |slice|
    [ 0.0 + slice[0].to_f,
      beat_seconds * 2.0 + slice[2].to_f ]
  end.uniq
  parts = kicks.first(64).map do |offset|
    t_mod = "mod(t-#{offset.round(6)},#{(beat_seconds * 4.0).round(6)})"
    "0.72*sin(2*PI*(46+88*exp(-#{t_mod}*20))*#{t_mod})*exp(-#{t_mod}*10)"
  end
  "(#{parts.join('+')})"
rescue StandardError
  "0.72*sin(2*PI*(46+88*exp(-mod(t,#{(beat_seconds * 2.0).round(6)})*18))*t)*exp(-mod(t,#{(beat_seconds * 2.0).round(6)})*9)"
end

# Snare on 2 and 4 with drunk timing + ghost notes at 1/8th positions.
def dilla_snare_expr(duration, drunk)
  beat2  = beat_seconds + (drunk[1] || 0.0)
  beat4  = beat_seconds * 3.0 + (drunk[3] || 0.0)
  bar    = beat_seconds * 4.0
  ghosts = [beat_seconds * 0.5, beat_seconds * 1.5, beat_seconds * 2.5, beat_seconds * 3.5].map do |pos|
    t_mod = "mod(t-#{pos.round(4)},#{bar.round(6)})"
    "0.05*(random(0)-0.5)*lt(#{t_mod},0.04)*exp(-#{t_mod}*50)"
  end
  main = [beat2, beat4].map do |pos|
    t_mod = "mod(t-#{pos.round(4)},#{bar.round(6)})"
    "0.52*(random(1)-0.5)*lt(#{t_mod},0.06)*exp(-#{t_mod}*28)"
  end
  "(#{(main + ghosts).join('+').gsub(/"/, '')})"
end

# Warbling Dilla bass: frequency modulated by an LFO for that loose,
# slightly sharp-flat feel. Octave sub below + harmonic above.
def dilla_bass_expr(root_hz = 43.0)
  lfo_rate = 0.12
  lfo_amt  = root_hz * 0.03
  fund     = "#{root_hz}+#{lfo_amt}*sin(2*PI*#{lfo_rate}*t)"
  "0.60*sin(2*PI*(#{fund})*t)+0.10*sin(2*PI*2*(#{fund})*t)"
end

# Full Dilla-style render: event-scheduled drums, voice-led pads, sample chops.
def render_dilla(destination = File.join(ROOT, "dilla_beat.mp3"), bars_count = nil)
  abort "ffmpeg required" unless tool_available?("ffmpeg")
  FileUtils.mkdir_p(File.dirname(destination))
  n_bars   = bars_count || bars
  beat_p   = beat_seconds
  duration = (beat_p * 4.0 * n_bars).round(3)
  swing    = (ENV["SWING"] || "58").to_f
  pressure = ENV["PRESSURE"] == "1"
  polyrhythm = ENV["POLYRHYTHM"]
  pads     = voice_lead_chords(dilla_progression((ENV["PROGRESSION"] || :soul).to_sym))
  @dilla_cycle = (beat_p * 8.0).round(6)
  drums    = dilla_schedule(2, beat_p, pads, chord_bars: 4, drums_only: true, swing: swing, pressure: pressure, polyrhythm: polyrhythm)
  harmony  = dilla_schedule(n_bars, beat_p, pads, chord_bars: 4, swing: swing, pressure: pressure, polyrhythm: polyrhythm)
  events   = drums.merge(pad: harmony[:pad], chop: harmony[:chop])

  kick_expr = event_expr(events, :kick) { |t, v, *| kick_wave(t, v) }
  kick_expr = "0" if kick_expr.empty?
  bass_expr = events[:bass].map { |t, v| bass_wave(t, v, 43.0) }.join("+")
  bass_expr = "0" if bass_expr.empty?
  pad_expr  = events[:pad].each_with_index.map { |(t, v, chord, sustain), i| pad_wave(t, v, chord, sustain, i) }.join("+")
  pad_expr  = "0" if pad_expr.empty?
  chop_expr = events[:chop].map { |t, v, chord| chop_wave(t, v, chord) }.join("+")
  chop_expr = "0" if chop_expr.empty?
  snare_env = snare_env(events)
  hat_env   = hat_env(events, :hat)
  open_env  = hat_env(events, :open, decay: 11)
  pressure_expr = events.fetch(:pressure, []).map { |t, v, root_hz| pressure_wave(t, v, root_hz) }.join("+")
  pressure_expr = "0" if pressure_expr.empty?

  command = ["ffmpeg", "-y",
             "-f", "lavfi", "-i", "aevalsrc='#{kick_expr}':d=#{duration}:s=#{SAMPLE_RATE}",
             "-f", "lavfi", "-i", "aevalsrc='#{bass_expr}':d=#{duration}:s=#{SAMPLE_RATE}",
             "-f", "lavfi", "-i", "anoisesrc=color=white:r=#{SAMPLE_RATE}:amplitude=0.5:d=#{duration}",
             "-f", "lavfi", "-i", "anoisesrc=color=pink:r=#{SAMPLE_RATE}:amplitude=0.04:d=#{duration}",
             "-f", "lavfi", "-i", "aevalsrc='#{pad_expr}':d=#{duration}:s=#{SAMPLE_RATE}",
             "-f", "lavfi", "-i", "aevalsrc='#{chop_expr}':d=#{duration}:s=#{SAMPLE_RATE}"]

  sample_input = File.exist?(SAMPLE_CLEAN) ? 6 : nil
  command += ["-stream_loop", "-1", "-i", SAMPLE_CLEAN] if sample_input
  pressure_input = nil
  if pressure
    pressure_input = sample_input ? 7 : 6
    command += ["-f", "lavfi", "-i", "aevalsrc='#{pressure_expr}':d=#{duration}:s=#{SAMPLE_RATE}"]
  end

  command += ["-filter_complex", dilla_drum_filter(snare_env, hat_env, open_env, pad_expr, chop_expr, duration, sample_input: sample_input, pressure_input: pressure_input),
              "-map", "[out]", "-t", duration.to_s, *loop_metadata_args(duration), *codec_for(destination), destination]
  sh!(*command)
  write_loop_metadata(destination, beat_p, n_bars, duration)
  puts "wrote #{destination} (#{bpm.to_i} BPM, #{n_bars} bars, Dilla Time scheduling)"
end

# --- Industrial techno engine (Hate podcast aesthetic) ---
# 130 BPM, E Phrygian, sawtooth/square waveforms, probability hats,
# sidechain compression, dotted-8th delay, long-tail reverb.

INDUSTRIAL_BPM_DEFAULT = 130.0

def render_industrial(destination = File.join(ROOT, "industrial.mp3"))
  abort "ffmpeg required" unless tool_available?("ffmpeg")
  FileUtils.mkdir_p(File.dirname(destination))
  ibpm      = ENV.fetch("IBPM", INDUSTRIAL_BPM_DEFAULT.to_s).to_f
  beat_p    = (60.0 / ibpm).round(6)
  n_bars    = [bars, (120.0 / (beat_p * 4)).ceil].max
  duration  = (beat_p * 4.0 * n_bars).round(3)
  bar_p     = (beat_p * 4.0).round(6)
  hat16_p   = (beat_p / 4.0).round(6)
  eighth_p  = (beat_p / 2.0).round(6)
  step_p    = (bar_p / 16.0).round(6)

  # Kick: sine sweep + sawtooth body, tanh saturation, strict 4/4, zero swing
  kick_expr = "tanh(4.0*(" \
              "0.28*(2*mod(50.0*t,1)-1)+" \
              "sin(2*PI*(50+165*exp(-mod(t,#{beat_p})*28))*t)" \
              ")*exp(-mod(t,#{beat_p})*7))"

  # Clap on 2+4: noise burst with per-bar amplitude variation (micro-dynamics)
  b2        = beat_p.round(6)
  b4        = (beat_p * 3.0).round(6)
  clap_vel  = "0.52+0.43*abs(sin(floor(t/#{bar_p})*43.758+12.1))"
  clap_expr = "(#{clap_vel})*(random(1)-0.5)*lt(mod(t-#{b2},#{bar_p}),0.038)*exp(-mod(t-#{b2},#{bar_p})*26)" \
              "+(#{clap_vel})*(random(2)-0.5)*lt(mod(t-#{b4},#{bar_p}),0.038)*exp(-mod(t-#{b4},#{bar_p})*26)"

  # Hi-hats: ~70% probability per 16th note via deterministic step hash
  hat_rand  = "abs(sin(floor(t/#{hat16_p})*127.1+311.7))"
  hat_expr  = "gt(#{hat_rand},0.35)*0.19*(random(3)-0.5)*lt(mod(t,#{hat16_p}),0.013)*exp(-mod(t,#{hat16_p})*70)"

  # Bass: sawtooth, E2 root (82.41 Hz), Bb1 tritone (58.27 Hz) on steps 8-9
  # Slow LFO simulates resonant filter sweep; gate on 8th notes
  step8_mid = (step_p * 9.0).round(4)
  note_expr = "if(lte(abs(mod(t,#{bar_p})-#{step8_mid}),#{step_p}),58.27,82.41)"
  bass_lfo  = "(0.50+0.50*sin(2*PI*0.15*t))"
  bass_gate = "lt(mod(t,#{eighth_p}),#{(eighth_p * 0.60).round(6)})"
  bass_expr = "0.88*(2*mod((#{note_expr})*t,1)-1)*#{bass_gate}*#{bass_lfo}*exp(-mod(t,#{eighth_p})*6)"

  # Chord stab: E minor square (E3+B3), short burst per bar, slow LFO envelope
  stab_lfo  = "0.44+0.56*abs(sin(2*PI*0.09*t))"
  stab_gate = "0.48*lt(mod(t,#{bar_p}),0.042)*exp(-mod(t,#{bar_p})*28)"
  stab_expr = "(0.24*sgn(sin(2*PI*164.81*t))+0.18*sgn(sin(2*PI*246.94*t)))*#{stab_gate}*(#{stab_lfo})"

  # Noise atmosphere: white noise with very slow breathing LFO (~20s cycle)
  noise_expr = "(random(7)-0.5)*(0.18+0.82*abs(sin(2*PI*0.05*t)))*0.08"

  dotted_8th_ms = (3.0 * beat_p / 4.0 * 1000.0).round(1)

  command = ["ffmpeg", "-y",
             "-f", "lavfi", "-i", "aevalsrc='#{kick_expr}':d=#{duration}:s=#{SAMPLE_RATE}",
             "-f", "lavfi", "-i", "aevalsrc='#{clap_expr}':d=#{duration}:s=#{SAMPLE_RATE}",
             "-f", "lavfi", "-i", "aevalsrc='#{hat_expr}':d=#{duration}:s=#{SAMPLE_RATE}",
             "-f", "lavfi", "-i", "aevalsrc='#{bass_expr}':d=#{duration}:s=#{SAMPLE_RATE}",
             "-f", "lavfi", "-i", "aevalsrc='#{stab_expr}':d=#{duration}:s=#{SAMPLE_RATE}",
             "-f", "lavfi", "-i", "aevalsrc='#{noise_expr}':d=#{duration}:s=#{SAMPLE_RATE}"]

  filter = []
  # Kick: shape, boost 58Hz, split into 3 for two sidechain feeds + main mix
  filter << "[0:a]aformat=channel_layouts=stereo," \
            "lowpass=f=250,acompressor=threshold=-8dB:ratio=12:attack=1:release=28," \
            "equalizer=f=58:width_type=o:width=2:g=6,asplit=3[kick][kick_sc1][kick_sc2]"
  # Clap: highpass, compress
  filter << "[1:a]aformat=channel_layouts=stereo," \
            "highpass=f=900,lowpass=f=14000,acompressor=threshold=-14dB:ratio=6:attack=2:release=40[clap]"
  # Hats: highpass only (probability already encoded in expression)
  filter << "[2:a]aformat=channel_layouts=stereo,highpass=f=7000[hats]"
  # Bass: shape, then sidechain-compress from kick — the "pumping" effect
  filter << "[3:a]aformat=channel_layouts=stereo," \
            "lowpass=f=450,equalizer=f=80:width_type=o:width=2:g=4[bass_pre]"
  filter << "[bass_pre][kick_sc1]sidechaincompress=threshold=-20dB:ratio=8:attack=1:release=80:level_sc=0.9[bass]"
  # Stab: shape, sidechain-compress from kick
  filter << "[4:a]aformat=channel_layouts=stereo,lowpass=f=5000,highpass=f=100[stab_pre]"
  filter << "[stab_pre][kick_sc2]sidechaincompress=threshold=-18dB:ratio=6:attack=3:release=120:level_sc=0.7[stab]"
  # Noise atmosphere: bandpass
  filter << "[5:a]aformat=channel_layouts=stereo,highpass=f=200,lowpass=f=6000[noise]"
  # Mix
  filter << "[kick][clap][hats][bass][stab][noise]" \
            "amix=inputs=6:weights=1.00 0.50 0.25 0.70 0.32 0.15:duration=first[mix]"
  # Reverb: long dark hall (4-6s tail) via multi-tap aecho
  filter << "[mix]asplit=2[dry][rev_send]"
  filter << "[rev_send]highpass=f=150," \
            "aecho=0.62:0.72:700|1300|2200|3800|6000:0.52|0.42|0.32|0.22|0.12[verb]"
  filter << "[dry][verb]amix=inputs=2:weights=0.70 0.30[with_reverb]"
  # Dotted 8th delay synced to tempo, 70-80% feedback, stereo spread
  filter << "[with_reverb]asplit=2[dry2][dly_send]"
  filter << "[dly_send]highpass=f=400," \
            "aecho=0.52:0.58:#{dotted_8th_ms}|#{(dotted_8th_ms * 1.48).round(1)}:0.75|0.65[dly]"
  filter << "[dry2][dly]amix=inputs=2:weights=0.78 0.22[predist]"
  # Master: tanh saturation, heavy compression, bit crush, tilt EQ, hard limit
  sat = Math.tanh(3.0).round(6)
  filter << "[predist]" \
            "aeval=exprs='tanh(3.0*val(0))/#{sat}|tanh(3.0*val(1))/#{sat}'," \
            "acompressor=threshold=-14dB:ratio=8:attack=1:release=55:makeup=4," \
            "acrusher=bits=14:samples=2:mix=0.12," \
            "equalizer=f=70:width_type=o:width=2:g=3," \
            "equalizer=f=9500:width_type=o:width=2:g=-3," \
            "alimiter=limit=0.94:level_out=0.96[out]"

  command += ["-filter_complex", filter.join(";"), "-map", "[out]", "-t", duration.to_s, *codec_for(destination), destination]
  sh!(*command)
  puts "wrote #{destination} (#{ibpm.to_i} BPM, #{n_bars} bars, #{duration}s)"
end

def render_neosoul(destination = File.join(ROOT, "neosoul.mp3"))
  abort "ffmpeg required" unless tool_available?("ffmpeg")
  FileUtils.mkdir_p(File.dirname(destination))
  srand(rand(999_999))

  d_bpm      = 80 + rand(12)
  drunk_ms   = (10 + rand(18)) / 1000.0
  pad_rotate = rand(JAZZ_CHORDS.length)
  pad_set    = JAZZ_CHORDS.rotate(pad_rotate)
  pad_lfo    = (0.03 + rand * 0.08).round(3)
  bass_root  = (38.0 + rand * 10.0).round(2)
  lfo_rate   = (0.06 + rand * 0.10).round(3)

  beat_p   = (60.0 / d_bpm.to_f).round(6)
  n_bars   = [bars, (120.0 / (beat_p * 4)).ceil].max
  duration = (beat_p * 4.0 * n_bars).round(3)
  bar_p    = (beat_p * 4.0).round(6)
  hat_p    = (beat_p / 2.0).round(6)

  drunk  = n_bars.times.flat_map { 4.times.map { (rand * 2 - 1) * drunk_ms } }

  chord_expr = chord_expr_for(pad_set, beat_p, pad_lfo, style: :rhodes)

  kicks = drunk.each_slice(4).flat_map { |s| [0.0 + s[0].to_f, beat_p * 2.0 + s[2].to_f] }.uniq
  kick_parts = kicks.first(64).map do |off|
    tm = "mod(t-#{off.round(6)},#{(beat_p * 4.0).round(6)})"
    "0.65*sin(2*PI*(44+80*exp(-#{tm}*22))*#{tm})*exp(-#{tm}*11)"
  end
  kick_expr = "(#{kick_parts.join('+')})"

  beat2   = beat_p + (drunk[1] || 0.0)
  beat4   = beat_p * 3.0 + (drunk[3] || 0.0)
  bar_val = (beat_p * 4.0).round(6)
  ghosts  = [beat_p * 0.5, beat_p * 1.5, beat_p * 2.5, beat_p * 3.5].map do |pos|
    tm = "mod(t-#{pos.round(4)},#{bar_val})"
    "0.04*(random(0)-0.5)*lt(#{tm},0.04)*exp(-#{tm}*50)"
  end
  snare_main = [beat2, beat4].map do |pos|
    tm = "mod(t-#{pos.round(4)},#{bar_val})"
    "0.48*(random(1)-0.5)*lt(#{tm},0.06)*exp(-#{tm}*28)"
  end
  snare_expr = "(#{(snare_main + ghosts).join('+').gsub(/"/, '')})"

  hat_off  = (drunk[0] || 0.0) * 0.5
  hat_expr = euclidean_hat_expr(11, 16, hat_p, amplitude: 0.14)
  hat_expr = "0.11*(random(2)-0.5)*lt(mod(t+#{hat_off.abs.round(4)},#{hat_p}),0.025)*exp(-mod(t,#{hat_p})*90)" if hat_expr.empty?
  lfo_amt  = bass_root * 0.03
  bass_expr = "0.55*sin(2*PI*(#{bass_root}+#{lfo_amt.round(3)}*sin(2*PI*#{lfo_rate}*t))*t)" \
              "+0.09*sin(2*PI*2*(#{bass_root}+#{lfo_amt.round(3)}*sin(2*PI*#{lfo_rate}*t))*t)"

  command = ["ffmpeg", "-y",
             "-f", "lavfi", "-i", "aevalsrc='#{chord_expr}':d=#{duration}:s=#{SAMPLE_RATE}",
             "-f", "lavfi", "-i", "aevalsrc='#{bass_expr}':d=#{duration}:s=#{SAMPLE_RATE}",
             "-f", "lavfi", "-i", "aevalsrc='#{kick_expr}':d=#{duration}:s=#{SAMPLE_RATE}",
             "-f", "lavfi", "-i", "aevalsrc='#{snare_expr}':d=#{duration}:s=#{SAMPLE_RATE}",
             "-f", "lavfi", "-i", "aevalsrc='#{hat_expr}':d=#{duration}:s=#{SAMPLE_RATE}"]

  labels  = %w[[pads] [bass] [kick] [snare] [hats]]
  weights = %w[0.88 0.88 0.78 0.55 0.18]
  filter  = []
  filter << "[0:a]aformat=channel_layouts=stereo,lowpass=f=5000,adelay=4|9[pads]"
  filter << "[1:a]aformat=channel_layouts=stereo,lowpass=f=200,equalizer=f=80:width_type=o:width=2:g=3[bass]"
  filter << "[2:a]aformat=channel_layouts=stereo,lowpass=f=160[kick]"
  filter << "[3:a]aformat=channel_layouts=stereo,highpass=f=180,lowpass=f=7000[snare]"
  filter << "[4:a]aformat=channel_layouts=stereo,highpass=f=6000[hats]"
  sat = Math.tanh(1.4).round(6)
  mix_chain = "#{labels.join}amix=inputs=#{labels.length}:weights=#{weights.join(' ')}:duration=first," \
              "aeval=exprs='tanh(1.4*val(0))/#{sat}|tanh(1.4*val(1))/#{sat}'," \
              "acompressor=threshold=-20dB:ratio=2.2:attack=22:release=140," \
              "acrusher=bits=13:samples=2:mix=0.10," \
              "alimiter=limit=0.92:level_out=0.94[out]"
  filter << mix_chain

  command += ["-filter_complex", filter.join(";"), "-map", "[out]", "-t", duration.to_s, *codec_for(destination), destination]
  sh!(*command)
  puts "    #{d_bpm} BPM  neosoul  pad_rotate=#{pad_rotate}  bass=#{bass_root}Hz"
end

def render_modal(destination = File.join(ROOT, "modal.mp3"))
  abort "ffmpeg required" unless tool_available?("ffmpeg")
  FileUtils.mkdir_p(File.dirname(destination))
  srand(rand(999_999))

  d_bpm      = 78 + rand(16)
  drunk_ms   = (8 + rand(16)) / 1000.0
  pad_rotate = rand(MODAL_CHORDS.length)
  pad_set    = MODAL_CHORDS.rotate(pad_rotate)
  pad_lfo    = (0.02 + rand * 0.06).round(3)
  bass_root  = (36.0 + rand * 12.0).round(2)
  lfo_rate   = (0.05 + rand * 0.09).round(3)

  beat_p   = (60.0 / d_bpm.to_f).round(6)
  n_bars   = [bars, (120.0 / (beat_p * 4)).ceil].max
  duration = (beat_p * 4.0 * n_bars).round(3)
  bar_p    = (beat_p * 4.0).round(6)
  hat_p    = (beat_p / 2.0).round(6)

  drunk  = n_bars.times.flat_map { 4.times.map { (rand * 2 - 1) * drunk_ms } }

  chord_expr = chord_expr_for(pad_set, beat_p, pad_lfo, style: :sine)

  kick_expr = halftime_kick_expr(beat_p)

  beat2   = beat_p + (drunk[1] || 0.0)
  beat4   = beat_p * 3.0 + (drunk[3] || 0.0)
  bar_val = (beat_p * 4.0).round(6)
  ghosts  = [beat_p * 0.75, beat_p * 1.75, beat_p * 2.75].map do |pos|
    tm = "mod(t-#{pos.round(4)},#{bar_val})"
    "0.04*(random(0)-0.5)*lt(#{tm},0.035)*exp(-#{tm}*55)"
  end
  snare_main = [beat2, beat4].map do |pos|
    tm = "mod(t-#{pos.round(4)},#{bar_val})"
    "0.45*(random(1)-0.5)*lt(#{tm},0.055)*exp(-#{tm}*30)"
  end
  snare_expr = "(#{(snare_main + ghosts).join('+').gsub(/"/, '')})"

  hat_expr = euclidean_hat_expr(7, 12, hat_p, amplitude: 0.12)
  hat_expr = "0.10*(random(2)-0.5)*lt(mod(t,#{hat_p}),0.022)*exp(-mod(t,#{hat_p})*95)" if hat_expr.empty?
  lfo_amt  = bass_root * 0.025
  bass_expr = "0.58*sin(2*PI*(#{bass_root}+#{lfo_amt.round(3)}*sin(2*PI*#{lfo_rate}*t))*t)" \
              "+0.08*sin(2*PI*2*(#{bass_root}+#{lfo_amt.round(3)}*sin(2*PI*#{lfo_rate}*t))*t)"

  command = ["ffmpeg", "-y",
             "-f", "lavfi", "-i", "aevalsrc='#{chord_expr}':d=#{duration}:s=#{SAMPLE_RATE}",
             "-f", "lavfi", "-i", "aevalsrc='#{bass_expr}':d=#{duration}:s=#{SAMPLE_RATE}",
             "-f", "lavfi", "-i", "aevalsrc='#{kick_expr}':d=#{duration}:s=#{SAMPLE_RATE}",
             "-f", "lavfi", "-i", "aevalsrc='#{snare_expr}':d=#{duration}:s=#{SAMPLE_RATE}",
             "-f", "lavfi", "-i", "aevalsrc='#{hat_expr}':d=#{duration}:s=#{SAMPLE_RATE}"]

  labels  = %w[[pads] [bass] [kick] [snare] [hats]]
  weights = %w[0.90 0.85 0.75 0.52 0.16]
  filter  = []
  filter << "[0:a]aformat=channel_layouts=stereo,lowpass=f=6000,adelay=6|14[pads]"
  filter << "[1:a]aformat=channel_layouts=stereo,lowpass=f=190,equalizer=f=75:width_type=o:width=2:g=3[bass]"
  filter << "[2:a]aformat=channel_layouts=stereo,lowpass=f=170[kick]"
  filter << "[3:a]aformat=channel_layouts=stereo,highpass=f=190,lowpass=f=7500[snare]"
  filter << "[4:a]aformat=channel_layouts=stereo,highpass=f=7500[hats]"
  sat = Math.tanh(1.3).round(6)
  mix_chain = "#{labels.join}amix=inputs=#{labels.length}:weights=#{weights.join(' ')}:duration=first," \
              "aeval=exprs='tanh(1.3*val(0))/#{sat}|tanh(1.3*val(1))/#{sat}'," \
              "acompressor=threshold=-21dB:ratio=2.0:attack=25:release=150," \
              "alimiter=limit=0.91:level_out=0.93[out]"
  filter << mix_chain

  command += ["-filter_complex", filter.join(";"), "-map", "[out]", "-t", duration.to_s, *codec_for(destination), destination]
  sh!(*command)
  puts "    #{d_bpm} BPM  modal  pad_rotate=#{pad_rotate}  bass=#{bass_root}Hz"
end

def render_gospel(destination = File.join(ROOT, "gospel.mp3"))
  abort "ffmpeg required" unless tool_available?("ffmpeg")
  FileUtils.mkdir_p(File.dirname(destination))
  srand(rand(999_999))

  d_bpm      = 72 + rand(20)
  drunk_ms   = (6 + rand(14)) / 1000.0
  pad_rotate = rand(GOSPEL_CHORDS.length)
  pad_set    = GOSPEL_CHORDS.rotate(pad_rotate)
  pad_lfo    = (0.04 + rand * 0.09).round(3)
  bass_root  = (41.0 + rand * 8.0).round(2)
  lfo_rate   = (0.05 + rand * 0.08).round(3)

  beat_p   = (60.0 / d_bpm.to_f).round(6)
  n_bars   = [bars, (120.0 / (beat_p * 4)).ceil].max
  duration = (beat_p * 4.0 * n_bars).round(3)
  bar_p    = (beat_p * 4.0).round(6)
  hat_p    = (beat_p / 2.0).round(6)

  drunk  = n_bars.times.flat_map { 4.times.map { (rand * 2 - 1) * drunk_ms } }

  chord_expr = chord_expr_for(pad_set, beat_p, pad_lfo, style: :hammond)

  kicks = drunk.each_slice(4).flat_map { |s| [0.0 + s[0].to_f, beat_p * 2.0 + s[2].to_f] }.uniq
  kick_parts = kicks.first(64).map do |off|
    tm = "mod(t-#{off.round(6)},#{(beat_p * 4.0).round(6)})"
    "0.68*sin(2*PI*(44+82*exp(-#{tm}*19))*#{tm})*exp(-#{tm}*9)"
  end
  kick_expr = "(#{kick_parts.join('+')})"

  beat2   = beat_p + (drunk[1] || 0.0)
  beat4   = beat_p * 3.0 + (drunk[3] || 0.0)
  bar_val = (beat_p * 4.0).round(6)
  snare_main = [beat2, beat4].map do |pos|
    tm = "mod(t-#{pos.round(4)},#{bar_val})"
    "0.55*(random(1)-0.5)*lt(#{tm},0.065)*exp(-#{tm}*25)"
  end
  snare_expr = "(#{snare_main.join('+').gsub(/"/, '')})"

  hat_expr = euclidean_hat_expr(9, 16, hat_p, amplitude: 0.15)
  hat_expr = "0.12*(random(2)-0.5)*lt(mod(t,#{hat_p}),0.022)*exp(-mod(t,#{hat_p})*88)" if hat_expr.empty?
  lfo_amt  = bass_root * 0.035
  bass_expr = "0.62*sin(2*PI*(#{bass_root}+#{lfo_amt.round(3)}*sin(2*PI*#{lfo_rate}*t))*t)" \
              "+0.11*sin(2*PI*2*(#{bass_root}+#{lfo_amt.round(3)}*sin(2*PI*#{lfo_rate}*t))*t)"

  command = ["ffmpeg", "-y",
             "-f", "lavfi", "-i", "aevalsrc='#{chord_expr}':d=#{duration}:s=#{SAMPLE_RATE}",
             "-f", "lavfi", "-i", "aevalsrc='#{bass_expr}':d=#{duration}:s=#{SAMPLE_RATE}",
             "-f", "lavfi", "-i", "aevalsrc='#{kick_expr}':d=#{duration}:s=#{SAMPLE_RATE}",
             "-f", "lavfi", "-i", "aevalsrc='#{snare_expr}':d=#{duration}:s=#{SAMPLE_RATE}",
             "-f", "lavfi", "-i", "aevalsrc='#{hat_expr}':d=#{duration}:s=#{SAMPLE_RATE}"]

  labels  = %w[[pads] [bass] [kick] [snare] [hats]]
  weights = %w[0.82 0.92 0.80 0.60 0.19]
  filter  = []
  filter << "[0:a]aformat=channel_layouts=stereo,lowpass=f=4500,adelay=3|8[pads]"
  filter << "[1:a]aformat=channel_layouts=stereo,lowpass=f=210,equalizer=f=85:width_type=o:width=2:g=4[bass]"
  filter << "[2:a]aformat=channel_layouts=stereo,lowpass=f=165[kick]"
  filter << "[3:a]aformat=channel_layouts=stereo,highpass=f=195,lowpass=f=6500[snare]"
  filter << "[4:a]aformat=channel_layouts=stereo,highpass=f=6500[hats]"
  sat = Math.tanh(1.5).round(6)
  mix_chain = "#{labels.join}amix=inputs=#{labels.length}:weights=#{weights.join(' ')}:duration=first," \
              "aeval=exprs='tanh(1.5*val(0))/#{sat}|tanh(1.5*val(1))/#{sat}'," \
              "acompressor=threshold=-18dB:ratio=2.4:attack=20:release=130," \
              "acrusher=bits=13:samples=2:mix=0.12," \
              "alimiter=limit=0.93:level_out=0.95[out]"
  filter << mix_chain

  command += ["-filter_complex", filter.join(";"), "-map", "[out]", "-t", duration.to_s, *codec_for(destination), destination]
  sh!(*command)
  puts "    #{d_bpm} BPM  gospel  pad_rotate=#{pad_rotate}  bass=#{bass_root}Hz"
end

# --- Batch generation: fitness-scored stochastic variants ---
# Fitness: target -14 dBFS mean loudness (streaming standard).
# Each variant is seeded for reproducibility; best seed is logged.

def track_score(path)
  return 0.0 unless tool_available?("ffprobe") && File.exist?(path)
  report = media_metadata(path).merge(volume_metadata(path))
  mean   = report[:mean_volume_db].to_f
  peak   = report[:max_volume_db].to_f
  return 0.0 if mean.zero? || mean < -32.0 || peak > -0.1
  100.0 - (mean + 14.0).abs * 2.5
rescue StandardError
  0.0
end

def batch_render(n, base_dest)
  ext      = File.extname(base_dest)
  variants = n.times.map do |i|
    seed = rand(999_999)
    dest = base_dest.sub(/#{Regexp.escape(ext)}\z/, "_v#{i + 1}s#{seed}#{ext}")
    puts "\n[#{i + 1}/#{n}] seed=#{seed}"
    yield seed, dest
    score = track_score(dest)
    puts "    score=#{score.round(1)}"
    { dest: dest, score: score, seed: seed }
  end
  best = variants.max_by { |v| v[:score] }
  puts "\nbest: seed #{best[:seed]}  score #{best[:score].round(1)}"
  FileUtils.cp(best[:dest], base_dest)
  variants.each { |v| File.delete(v[:dest]) rescue nil }
  puts "wrote #{base_dest}"
  best
end

def chord_expr_for(pad_chords, beat_s, lfo_rate, style: :sine)
  cycle = (pad_chords.length * 8.0 * beat_s).round(4)
  parts = pad_chords.each_with_index.map do |chord, ci|
    t0 = (ci * 8.0 * beat_s).round(4)
    t1 = (t0 + 8.0 * beat_s).round(4)
    voices = chord[:hz].each_with_index.map do |f, vi|
      detune = 1.0 + ((vi - 2) * 0.0015)
      gain   = (0.018 + vi * 0.002).round(4)
      fd     = (f * detune).round(4)
      case style
      when :sine
        "#{gain}*sin(2*PI*#{fd}*t)"
      when :rhodes
        "#{gain}*(sin(2*PI*#{fd}*t)+0.08*sin(2*PI*#{(fd * 3).round(4)}*t))*(0.78+0.22*sin(2*PI*6.5*t))"
      when :wurlitzer
        "#{gain}*(sin(2*PI*#{fd}*t)+0.25*sin(2*PI*#{(fd * 3).round(4)}*t)+0.12*sin(2*PI*#{(fd * 5).round(4)}*t))"
      when :hammond
        "#{gain}*(0.9*sin(2*PI*#{(fd * 0.5).round(4)}*t)+sin(2*PI*#{fd}*t)+0.8*sin(2*PI*#{(fd * 1.5).round(4)}*t)+0.5*sin(2*PI*#{(fd * 2.0).round(4)}*t))"
      when :super_saw
        [-0.008, 0.0, 0.008].map do |d|
          df = (fd * (1 + d)).round(4)
          "#{gain}*(2*mod(#{df}*t,1)-1)"
        end.join("+")
      when :choir
        [0.0, 0.52, 1.05, 1.57].each_with_index.map do |phase, pvi|
          cf = (fd * (1 + (pvi - 1.5) * 0.0008)).round(4)
          "#{gain}*sin(2*PI*#{cf}*t+#{phase})"
        end.join("+")
      when :fm_bell
        "#{gain}*sin(2*PI*#{fd}*t+3.0*sin(2*PI*#{(fd * 1.007).round(4)}*t))"
      end
    end.join("+")
    "between(mod(t,#{cycle}),#{t0},#{t1})*(#{voices})"
  end.join("+")
  "(#{parts})*(0.52+0.48*sin(2*PI*#{lfo_rate}*t))"
end

def render_industrial_variant(seed, destination)
  abort "ffmpeg required" unless tool_available?("ffmpeg")
  FileUtils.mkdir_p(File.dirname(destination))
  srand(seed)

  ibpm       = 128 + rand(11)
  kick_base  = 46 + rand(14)
  kick_sweep = (kick_base * 2.2 + rand(20)).round(1)
  kick_drive = (3.2 + rand * 2.2).round(2)
  root_hz    = [82.41, 73.42, 92.50, 69.30, 98.00, 77.78].sample
  tritone_hz = (root_hz * Math.sqrt(2)).round(2)
  stab_root  = (root_hz * 2).round(2)
  stab_fifth = (root_hz * 3).round(2)
  bass_lfo   = (0.08 + rand * 0.17).round(3)
  stab_lfo   = (0.05 + rand * 0.12).round(3)
  noise_lfo  = (0.03 + rand * 0.06).round(3)
  hat_thr    = (0.22 + rand * 0.28).round(3)
  rev_times  = 4.times.map { |j| 500 + j * 700 + rand(300) }
  rev_decays = [0.55, 0.44, 0.33, 0.22]
  dotted_ratio = 1.40 + rand * 0.20

  beat_p   = (60.0 / ibpm.to_f).round(6)
  n_bars   = [bars, (120.0 / (beat_p * 4)).ceil].max
  duration = (beat_p * 4.0 * n_bars).round(3)
  bar_p    = (beat_p * 4.0).round(6)
  hat16_p  = (beat_p / 4.0).round(6)
  eighth_p = (beat_p / 2.0).round(6)
  step_p   = (bar_p / 16.0).round(6)
  b2 = beat_p.round(6)
  b4 = (beat_p * 3.0).round(6)
  dotted_8th_ms = (3.0 * beat_p / 4.0 * 1000.0).round(1)

  kick_expr = "tanh(#{kick_drive}*(0.28*(2*mod(#{kick_base}.0*t,1)-1)+" \
              "sin(2*PI*(#{kick_base}+#{kick_sweep}*exp(-mod(t,#{beat_p})*28))*t))" \
              "*exp(-mod(t,#{beat_p})*7))"
  clap_vel  = "0.52+0.43*abs(sin(floor(t/#{bar_p})*43.758+12.1))"
  clap_expr = "(#{clap_vel})*(random(1)-0.5)*lt(mod(t-#{b2},#{bar_p}),0.038)*exp(-mod(t-#{b2},#{bar_p})*26)" \
              "+(#{clap_vel})*(random(2)-0.5)*lt(mod(t-#{b4},#{bar_p}),0.038)*exp(-mod(t-#{b4},#{bar_p})*26)"
  hat_expr  = "gt(abs(sin(floor(t/#{hat16_p})*127.1+311.7)),#{hat_thr})" \
              "*0.19*(random(3)-0.5)*lt(mod(t,#{hat16_p}),0.013)*exp(-mod(t,#{hat16_p})*70)"
  step8_mid = (step_p * 9.0).round(4)
  note_expr = "if(lte(abs(mod(t,#{bar_p})-#{step8_mid}),#{step_p}),#{tritone_hz},#{root_hz})"
  bass_expr = "0.88*(2*mod((#{note_expr})*t,1)-1)" \
              "*lt(mod(t,#{eighth_p}),#{(eighth_p * 0.60).round(6)})" \
              "*(0.50+0.50*sin(2*PI*#{bass_lfo}*t))*exp(-mod(t,#{eighth_p})*6)"
  stab_expr = "(0.24*sgn(sin(2*PI*#{stab_root}*t))+0.18*sgn(sin(2*PI*#{stab_fifth}*t)))" \
              "*0.48*lt(mod(t,#{bar_p}),0.042)*exp(-mod(t,#{bar_p})*28)" \
              "*(0.44+0.56*abs(sin(2*PI*#{stab_lfo}*t)))"
  noise_expr = "(random(7)-0.5)*(0.18+0.82*abs(sin(2*PI*#{noise_lfo}*t)))*0.08"

  command = ["ffmpeg", "-y",
             "-f", "lavfi", "-i", "aevalsrc='#{kick_expr}':d=#{duration}:s=#{SAMPLE_RATE}",
             "-f", "lavfi", "-i", "aevalsrc='#{clap_expr}':d=#{duration}:s=#{SAMPLE_RATE}",
             "-f", "lavfi", "-i", "aevalsrc='#{hat_expr}':d=#{duration}:s=#{SAMPLE_RATE}",
             "-f", "lavfi", "-i", "aevalsrc='#{bass_expr}':d=#{duration}:s=#{SAMPLE_RATE}",
             "-f", "lavfi", "-i", "aevalsrc='#{stab_expr}':d=#{duration}:s=#{SAMPLE_RATE}",
             "-f", "lavfi", "-i", "aevalsrc='#{noise_expr}':d=#{duration}:s=#{SAMPLE_RATE}"]
  filter = []
  filter << "[0:a]aformat=channel_layouts=stereo,lowpass=f=250," \
            "acompressor=threshold=-8dB:ratio=12:attack=1:release=28," \
            "equalizer=f=#{kick_base}:width_type=o:width=2:g=6,asplit=3[kick][kick_sc1][kick_sc2]"
  filter << "[1:a]aformat=channel_layouts=stereo,highpass=f=900,lowpass=f=14000," \
            "acompressor=threshold=-14dB:ratio=6:attack=2:release=40[clap]"
  filter << "[2:a]aformat=channel_layouts=stereo,highpass=f=7000[hats]"
  filter << "[3:a]aformat=channel_layouts=stereo,lowpass=f=450," \
            "equalizer=f=#{root_hz.to_i}:width_type=o:width=2:g=4[bass_pre]"
  filter << "[bass_pre][kick_sc1]sidechaincompress=threshold=-20dB:ratio=8:attack=1:release=80:level_sc=0.9[bass]"
  filter << "[4:a]aformat=channel_layouts=stereo,lowpass=f=5000,highpass=f=100[stab_pre]"
  filter << "[stab_pre][kick_sc2]sidechaincompress=threshold=-18dB:ratio=6:attack=3:release=120:level_sc=0.7[stab]"
  filter << "[5:a]aformat=channel_layouts=stereo,highpass=f=200,lowpass=f=6000[noise]"
  filter << "[kick][clap][hats][bass][stab][noise]" \
            "amix=inputs=6:weights=1.00 0.50 0.25 0.70 0.32 0.15:duration=first[mix]"
  filter << "[mix]asplit=2[dry][rev_send]"
  filter << "[rev_send]highpass=f=150," \
            "aecho=0.62:0.72:#{rev_times.join('|')}:#{rev_decays.join('|')}[verb]"
  filter << "[dry][verb]amix=inputs=2:weights=0.70 0.30[with_reverb]"
  filter << "[with_reverb]asplit=2[dry2][dly_send]"
  filter << "[dly_send]highpass=f=400," \
            "aecho=0.52:0.58:#{dotted_8th_ms}|#{(dotted_8th_ms * dotted_ratio).round(1)}:0.75|0.65[dly]"
  filter << "[dry2][dly]amix=inputs=2:weights=0.78 0.22[predist]"
  sat = Math.tanh(3.0).round(6)
  filter << "[predist]aeval=exprs='tanh(3.0*val(0))/#{sat}|tanh(3.0*val(1))/#{sat}'," \
            "acompressor=threshold=-14dB:ratio=8:attack=1:release=55:makeup=4," \
            "acrusher=bits=14:samples=2:mix=0.12," \
            "equalizer=f=70:width_type=o:width=2:g=3," \
            "equalizer=f=9500:width_type=o:width=2:g=-3," \
            "alimiter=limit=0.94:level_out=0.96[out]"
  command += ["-filter_complex", filter.join(";"), "-map", "[out]", "-t", duration.to_s, *codec_for(destination), destination]
  sh!(*command)
  puts "    #{ibpm} BPM  root=#{root_hz}Hz  hat_thr=#{hat_thr}  bass_lfo=#{bass_lfo}"
end

def render_dilla_variant(seed, destination)
  abort "ffmpeg required" unless tool_available?("ffmpeg")
  FileUtils.mkdir_p(File.dirname(destination))
  srand(seed)

  d_bpm      = 84 + rand(15)
  pad_rotate = rand(PAD_CHORDS.length)
  pad_set    = voice_lead_chords(dilla_progression((ENV["PROGRESSION"] || :soul).to_sym).rotate(pad_rotate))
  bass_root  = (40.0 + rand * 10.0).round(2)

  beat_p   = (60.0 / d_bpm.to_f).round(6)
  n_bars   = [bars, (120.0 / (beat_p * 4)).ceil].max
  duration = (beat_p * 4.0 * n_bars).round(3)
  @dilla_cycle = (beat_p * 8.0).round(6)
  swing    = (ENV["SWING"] || "58").to_f
  pressure = ENV["PRESSURE"] == "1"
  polyrhythm = ENV["POLYRHYTHM"]
  drums    = dilla_schedule(2, beat_p, pad_set, chord_bars: 4, drums_only: true, swing: swing, pressure: pressure, polyrhythm: polyrhythm)
  harmony  = dilla_schedule(n_bars, beat_p, pad_set, chord_bars: 4, swing: swing, pressure: pressure, polyrhythm: polyrhythm)
  events   = drums.merge(pad: harmony[:pad], chop: harmony[:chop])

  kick_expr = event_expr(events, :kick) { |t, v, *| kick_wave(t, v) }
  kick_expr = "0" if kick_expr.empty?
  bass_expr = events[:bass].map { |t, v| bass_wave(t, v, bass_root) }.join("+")
  bass_expr = "0" if bass_expr.empty?
  pad_expr  = events[:pad].each_with_index.map { |(t, v, chord, sustain), i| pad_wave(t, v, chord, sustain, i) }.join("+")
  pad_expr  = "0" if pad_expr.empty?
  chop_expr = events[:chop].map { |t, v, chord| chop_wave(t, v, chord) }.join("+")
  chop_expr = "0" if chop_expr.empty?
  pressure_expr = events.fetch(:pressure, []).map { |t, v, root_hz| pressure_wave(t, v, root_hz) }.join("+")
  pressure_expr = "0" if pressure_expr.empty?

  command = ["ffmpeg", "-y",
             "-f", "lavfi", "-i", "aevalsrc='#{kick_expr}':d=#{duration}:s=#{SAMPLE_RATE}",
             "-f", "lavfi", "-i", "aevalsrc='#{bass_expr}':d=#{duration}:s=#{SAMPLE_RATE}",
             "-f", "lavfi", "-i", "anoisesrc=color=white:r=#{SAMPLE_RATE}:amplitude=0.5:d=#{duration}",
             "-f", "lavfi", "-i", "anoisesrc=color=pink:r=#{SAMPLE_RATE}:amplitude=0.04:d=#{duration}",
             "-f", "lavfi", "-i", "aevalsrc='#{pad_expr}':d=#{duration}:s=#{SAMPLE_RATE}",
             "-f", "lavfi", "-i", "aevalsrc='#{chop_expr}':d=#{duration}:s=#{SAMPLE_RATE}"]

  command += ["-f", "lavfi", "-i", "aevalsrc='#{pressure_expr}':d=#{duration}:s=#{SAMPLE_RATE}"] if pressure

  command += ["-filter_complex",
              dilla_drum_filter(snare_env(events), hat_env(events, :hat), hat_env(events, :open, decay: 11),
                                pad_expr, chop_expr, duration,
                                pressure_input: pressure ? 6 : nil),
              "-map", "[out]", "-t", duration.to_s, *loop_metadata_args(duration), *codec_for(destination), destination]
  sh!(*command)
  write_loop_metadata(destination, beat_p, n_bars, duration)
  puts "    #{d_bpm} BPM  Dilla Time  pad_rotate=#{pad_rotate}  bass=#{bass_root}Hz"
end

def batch_industrial(n = 5, destination = File.join(ROOT, "industrial.mp3"))
  batch_render(n, destination) { |seed, dest| render_industrial_variant(seed, dest) }
end

def batch_dilla(n = 5, destination = File.join(ROOT, "dilla_beat.mp3"))
  batch_render(n, destination) { |seed, dest| render_dilla_variant(seed, dest) }
end

def batch_neosoul(n = 5, destination = File.join(ROOT, "neosoul.mp3"))
  batch_render(n, destination) { |seed, dest| srand(seed); render_neosoul(dest) }
end

def batch_modal(n = 5, destination = File.join(ROOT, "modal.mp3"))
  batch_render(n, destination) { |seed, dest| srand(seed); render_modal(dest) }
end

def batch_gospel(n = 5, destination = File.join(ROOT, "gospel.mp3"))
  batch_render(n, destination) { |seed, dest| srand(seed); render_gospel(dest) }
end

# --- MIDI stack (Raymond Scott Electronium × J Dilla × Bach) ---

MIDI_F_MINOR    = [65, 67, 68, 70, 72, 73, 75].freeze
MIDI_CHORDS     = {
  fm7:    [65, 68, 72, 75],
  dbmaj7: [61, 65, 68, 72],
  eb7:    [63, 67, 70, 75],
  bbm7:   [58, 61, 65, 68],
  cm7b5:  [60, 63, 66, 70],
  c7:     [60, 64, 67, 70]
}.freeze
MIDI_PROGRESSION = %i[fm7 dbmaj7 eb7 bbm7 cm7b5 fm7 c7 fm7].freeze
MIDI_PPQN        = 480

module BachEngine
  FORBIDDEN_PARALLELS = [7, 12].freeze
  PREFERRED_INTERVALS = [3, 4, 5, 8, 9].freeze

  def self.valid_counterpoint?(mel, ctr, prev_mel, prev_ctr)
    interval = (mel - ctr).abs % 12
    return false if [0, 1, 11].include?(interval)
    if prev_mel && prev_ctr
      prev_interval = (prev_mel - prev_ctr).abs % 12
      m_dir = mel <=> prev_mel
      c_dir = ctr <=> prev_ctr
      return false if m_dir == c_dir && m_dir != 0 &&
                      FORBIDDEN_PARALLELS.include?(interval) && interval == prev_interval
    end
    true
  end

  def self.score_candidate(mel, ctr, prev_mel, prev_ctr)
    score = 0.0
    interval = (mel - ctr).abs % 12
    score += 3.0 if PREFERRED_INTERVALS.include?(interval)
    score -= 2.0 if [0, 1, 11].include?(interval)
    if prev_mel && prev_ctr
      mel_motion = (mel - prev_mel).abs
      ctr_motion = (ctr - prev_ctr).abs
      score += 2.0 if mel_motion <= 2 && ctr_motion <= 2
      score += 1.5 if (mel <=> prev_mel) != (ctr <=> prev_ctr) && mel != prev_mel && ctr != prev_ctr
      score -= 3.0 if mel_motion.zero? && ctr_motion.zero?
    end
    score
  end

  def self.generate_counterpoint(melody, scale)
    prev_m = prev_c = nil
    melody.map do |mel_note|
      valid = scale.select { |c| valid_counterpoint?(mel_note, c, prev_m, prev_c) }
      chosen = if valid.empty?
                 scale.sample
               else
                 valid.max_by { |c| score_candidate(mel_note, c, prev_m, prev_c) + rand * 0.4 }
               end
      prev_m, prev_c = mel_note, chosen
      chosen
    end
  end
end

module MelodyEngine
  def self.generate(num_notes, scale, octave: 0)
    notes = []
    index = 0
    direction = 1
    num_notes.times do |i|
      midi_note = scale[index] + (octave * 12)
      duration = if rand(10).zero? then 0
                 elsif rand(3).zero? then 0.5
                 else 1.0
                 end
      notes << { note: midi_note, start: i * 0.5, duration: duration, velocity: 80 + rand(-15..15) }
      step = rand(4).zero? ? rand(1..3) : 1
      index += direction * step
      if index >= scale.length
        index = scale.length - 2
        direction = -1
      elsif index < 0
        index = 1
        direction = 1
      end
      direction *= -1 if rand(4).zero?
    end
    notes
  end
end

module HarmonyEngine
  def self.generate(progression)
    chord_beats = 2.0
    progression.each_with_index.flat_map do |chord_name, i|
      start_ticks = (i * chord_beats * MIDI_PPQN).to_i
      MIDI_CHORDS.fetch(chord_name, []).map do |midi_note|
        { note: midi_note,
          start: start_ticks + rand(-4..4),
          duration: (chord_beats * MIDI_PPQN * 0.95).to_i,
          velocity: rand(40..70) }
      end
    end
  end
end

class MIDIExporter
  def initialize(tempo_bpm)
    @tempo_bpm = tempo_bpm
  end

  def export(filename, track_data)
    begin
      require "midilib"
      require "midilib/sequence"
      require "midilib/track"
      require "midilib/consts"
    rescue LoadError
      abort "midilib not installed — run: gem install midilib"
    end

    seq = MIDI::Sequence.new
    seq.ppqn = MIDI_PPQN

    tempo_track = MIDI::Track.new(seq)
    seq.tracks << tempo_track
    tempo_track.events << MIDI::Tempo.new(MIDI::Tempo.bpm_to_mpq(@tempo_bpm))
    tempo_track.events << MIDI::MetaEvent.new(MIDI::META_SEQ_NAME, "Dilla Electronium")

    { drums: 9, bass: 0, chords: 1, melody: 2, counterpoint: 3 }.each do |part, channel|
      events = track_data[part]
      next if events.nil? || events.empty?
      track = MIDI::Track.new(seq)
      seq.tracks << track
      events.each do |ev|
        next if ev[:duration].to_i <= 0
        on  = MIDI::NoteOn.new(channel, ev[:note], ev[:velocity])
        off = MIDI::NoteOff.new(channel, ev[:note], 0)
        on.time_from_start  = ev[:start].to_i
        off.time_from_start = (ev[:start] + ev[:duration]).to_i
        track.events << on << off
      end
      track.recalc_times
    end

    File.open(filename, "wb") { |f| seq.write(f) }
    puts "wrote #{filename}"
  end
end

def midi_generate(destination = File.join(ROOT, "dilla_electronium.mid"))
  n_bars   = bars
  beat_p   = beat_seconds
  ppqn     = MIDI_PPQN

  full_prog = []
  (n_bars / MIDI_PROGRESSION.length.to_f).ceil.times { full_prog.concat(MIDI_PROGRESSION) }

  chord_events = HarmonyEngine.generate(full_prog)

  raw_melody   = MelodyEngine.generate(n_bars * 8, MIDI_F_MINOR)
  melody_events = raw_melody.map { |n|
    n.merge(start: (n[:start] * ppqn).to_i, duration: (n[:duration] * ppqn).to_i)
  }
  counter_notes  = BachEngine.generate_counterpoint(raw_melody.map { |n| n[:note] }, MIDI_F_MINOR)
  counter_events = raw_melody.each_with_index.map { |n, i|
    { note: counter_notes[i], start: (n[:start] * ppqn).to_i,
      duration: (n[:duration] * ppqn).to_i, velocity: (n[:velocity] * 0.75).to_i }
  }

  drum_events = []
  (n_bars / 2.0).ceil.times do |bar_group|
    base = (bar_group * 8.0 * ppqn).to_i
    [0.0, 2.0, 4.0, 6.0].each do |beat|
      drum_events << { note: 36, start: base + (beat * ppqn).to_i + rand(-3..0), duration: ppqn / 2, velocity: 100 }
    end
    [1.0, 3.0, 5.0, 7.0].each do |beat|
      drum_events << { note: 38, start: base + (beat * ppqn).to_i + rand(0..5), duration: ppqn / 2, velocity: 90 }
    end
    8.times do |beat|
      [0, 3.0 / 7.0].each do |sub|
        drum_events << { note: 42, start: base + ((beat + sub) * ppqn).to_i + rand(-2..2), duration: ppqn / 5, velocity: rand(50..70) }
      end
    end
  end

  bass_events = []
  (n_bars / MIDI_PROGRESSION.length.to_f).ceil.times do |cycle|
    MIDI_PROGRESSION.each_with_index do |chord_name, ci|
      root = MIDI_CHORDS.fetch(chord_name, [65]).first - 24
      base = ((cycle * MIDI_PROGRESSION.length * 2.0 + ci * 2.0) * ppqn).to_i
      [0.0, 0.75].each do |off|
        bass_events << { note: root, start: base + (off * ppqn).to_i + rand(-4..4), duration: ppqn / 2, velocity: rand(90..110) }
      end
    end
  end

  MIDIExporter.new(bpm.to_i).export(destination, {
    drums: drum_events, bass: bass_events, chords: chord_events,
    melody: melody_events, counterpoint: counter_events
  })
end

groove_requested = ARGV.delete("--groove")

case ARGV.shift
when "scan" then scan(groove: groove_requested)
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
when "stems" then stems(ARGV.shift || File.join(ROOT, "samples/demucs"), ARGV.shift || File.join(ROOT, "samples/manifest.json"))
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
when "dilla"      then render_dilla(ARGV.shift || File.join(ROOT, "dilla_beat.mp3"))
when "midi"       then midi_generate(ARGV.shift || File.join(ROOT, "dilla_electronium.mid"))
when "industrial"       then render_industrial(ARGV.shift || File.join(ROOT, "industrial.mp3"))
when "batch_industrial" then batch_industrial((ARGV.shift || 5).to_i, ARGV.shift || File.join(ROOT, "industrial.mp3"))
when "batch_dilla"      then batch_dilla((ARGV.shift || 5).to_i, ARGV.shift || File.join(ROOT, "dilla_beat.mp3"))
when "neosoul"          then render_neosoul(ARGV.shift || File.join(ROOT, "neosoul.mp3"))
when "modal"            then render_modal(ARGV.shift || File.join(ROOT, "modal.mp3"))
when "gospel"           then render_gospel(ARGV.shift || File.join(ROOT, "gospel.mp3"))
when "batch_neosoul"    then batch_neosoul((ARGV.shift || 5).to_i, ARGV.shift || File.join(ROOT, "neosoul.mp3"))
when "batch_modal"      then batch_modal((ARGV.shift || 5).to_i, ARGV.shift || File.join(ROOT, "modal.mp3"))
when "batch_gospel"     then batch_gospel((ARGV.shift || 5).to_i, ARGV.shift || File.join(ROOT, "gospel.mp3"))
else
  puts "commands: #{COMMANDS.join(' | ')}"
end
