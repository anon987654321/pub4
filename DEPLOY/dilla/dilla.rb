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
  { name: "C cluster", hz: [130.81, 138.59, 196.00, 233.08, 311.13] }
].freeze
COMMANDS = %w[scan sweep council debug sample source livestream separate render verify chords clean stems study rhythm melody harmony semantics ears].freeze
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

def scan
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

case ARGV.shift
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
when "stems" then stems(ARGV.shift || File.join(ROOT, "samples/demucs"), ARGV.shift || File.join(ROOT, "samples/manifest.json"))
when "study" then study(ARGV.shift, ARGV.shift)
when "rhythm" then rhythm(ARGV.shift)
when "melody" then melody(ARGV.shift)
when "harmony" then harmony(ARGV.shift)
when "semantics" then semantics(ARGV.shift)
when "ears" then ears(ARGV.shift || File.join(ROOT, "full_track.mp3"))
else
  puts "commands: #{COMMANDS.join(' | ')}"
end
