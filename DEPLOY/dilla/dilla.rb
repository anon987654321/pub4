#!/usr/bin/env ruby
# frozen_string_literal: true
# dilla.rb — MASTER-shaped sample-first groove lab.
# Ruby only. Existing-file workflow. No background jobs.

require "fileutils"
require "json"
require "open3"

ROOT = File.expand_path(__dir__)
SAMPLE_DIR = File.join(ROOT, "samples")
STEM_DIR = File.join(ROOT, "stems")
DEFAULT_BPM = 84.0
DEFAULT_BARS = 40
SAMPLE_CLEAN = File.join(SAMPLE_DIR, "clean_harmonic.wav")
CHORDS = [
  ["Gm9", [196.00, 233.08, 293.66, 349.23, 440.00]],
  ["D7", [146.83, 185.00, 220.00, 261.63, 329.63]],
  ["Cm9", [130.81, 155.56, 196.00, 233.08, 293.66]],
  ["Fmaj7", [174.61, 220.00, 261.63, 329.63, 392.00]]
].freeze

Result = Struct.new(:ok?, :message, keyword_init: true)

def sh!(*cmd)
  puts ">>> #{cmd.flatten.join(' ')}"
  abort "failed: #{cmd.flatten.first}" unless system(*cmd.flatten.map(&:to_s))
end

def capture(*cmd)
  Open3.capture3(*cmd.flatten.map(&:to_s))
end

def command?(name)
  _out, _err, status = capture("sh", "-lc", "command -v #{name}")
  status.success?
end

def bpm
  (ENV["BPM"] || DEFAULT_BPM).to_f
end

def bars
  (ENV["BARS"] || DEFAULT_BARS).to_i
end

def seconds
  ((60.0 / bpm) * 4.0 * bars).round(3)
end

def beat
  60.0 / bpm
end

def chord_expr
  CHORDS.each_with_index.map do |(_name, freqs), idx|
    start = idx * 8.0 * beat
    stop = start + 8.0 * beat
    body = freqs.each_with_index.map do |freq, voice|
      detune = 1.0 + ((voice - 2) * 0.0015)
      "#{0.018 + voice * 0.002}*sin(2*PI*#{(freq * detune).round(4)}*t)"
    end.join("+")
    "between(mod(t,#{32.0 * beat}),#{start.round(4)},#{stop.round(4)})*(#{body})"
  end.join("+")
end

def scan
  payload = {
    root: ROOT,
    bpm: bpm,
    bars: bars,
    seconds: seconds,
    files: {
      ruby: File.exist?(__FILE__),
      html: File.exist?(File.join(ROOT, "dilla.html")),
      clean_harmonic: File.exist?(SAMPLE_CLEAN)
    },
    tools: {
      ffmpeg: command?("ffmpeg"),
      yt_dlp: command?("yt-dlp"),
      demucs: command?("demucs")
    }
  }
  puts JSON.pretty_generate(payload)
end

def council
  puts "MASTER council:"
  puts "- sample-first: synthetic render is fallback only"
  puts "- loop hypnosis: repeat harmonic centers longer than instinct says"
  puts "- correlated timing: hats late, snare early, bass behind kick"
  puts "- restraint: leave holes; avoid maximal DSP"
  puts "- debug gate: render, then verify mean and max volume"
end

def sample
  FileUtils.mkdir_p(SAMPLE_DIR)
  FileUtils.mkdir_p(STEM_DIR)
  puts "Paste YouTube URL for harmonic sample:"
  url = STDIN.gets&.strip
  abort "missing URL" if url.nil? || url.empty?

  sh! "yt-dlp", "-f", "bestaudio", "--extract-audio", "--audio-format", "wav", url, "-o", File.join(SAMPLE_DIR, "%(title)s.%(ext)s")
  wav = Dir[File.join(SAMPLE_DIR, "*.wav")].max_by { |path| File.mtime(path) }
  abort "download produced no wav" unless wav

  sh! "demucs", "-n", "htdemucs_ft", "-o", STEM_DIR, wav
  other = Dir[File.join(STEM_DIR, "**", "other.wav")].max_by { |path| File.mtime(path) }
  abort "demucs produced no other.wav harmonic stem" unless other

  sh! "ffmpeg", "-y", "-i", other,
      "-af", "highpass=f=85,lowpass=f=12000,afftdn=nf=-25,adeclick,loudnorm=I=-20:TP=-2:LRA=9",
      "-c:a", "pcm_s16le", SAMPLE_CLEAN
  puts "wrote #{SAMPLE_CLEAN}"
end

def render(dest = File.join(ROOT, "full_track.mp3"))
  abort "ffmpeg required" unless command?("ffmpeg")
  FileUtils.mkdir_p(File.dirname(dest))

  dur = seconds
  kick_period = (beat * 2).round(6)

  cmd = ["ffmpeg", "-y"]
  cmd += ["-f", "lavfi", "-i", "aevalsrc='#{chord_expr}':d=#{dur}:s=44100"]
  cmd += ["-f", "lavfi", "-i", "aevalsrc='0.16*sin(2*PI*49*t)*exp(-mod(t,#{beat.round(6)})*3.1)':d=#{dur}:s=44100"]
  cmd += ["-f", "lavfi", "-i", "aevalsrc='0.58*sin(2*PI*(45+90*exp(-mod(t,#{kick_period})*18))*t)*exp(-mod(t,#{kick_period})*9)':d=#{dur}:s=44100"]
  cmd += ["-f", "lavfi", "-i", "aevalsrc='0.13*(random(0)-0.5)*lt(mod(t+#{beat.round(6)},#{(beat * 2).round(6)}),0.08)*exp(-mod(t+#{beat.round(6)},#{(beat * 2).round(6)})*28)':d=#{dur}:s=44100"]
  cmd += ["-f", "lavfi", "-i", "aevalsrc='0.035*(random(0)-0.5)*lt(mod(t,#{(beat / 2).round(6)}),0.035)*exp(-mod(t,#{(beat / 2).round(6)})*80)':d=#{dur}:s=44100"]

  sample_index = nil
  if File.exist?(SAMPLE_CLEAN)
    sample_index = 5
    cmd += ["-stream_loop", "-1", "-i", SAMPLE_CLEAN]
  end

  filter = []
  filter << "[0:a]aformat=channel_layouts=stereo,lowpass=f=3300,adelay=7|13[ep]"
  filter << "[1:a]aformat=channel_layouts=stereo,lowpass=f=160[bass]"
  filter << "[2:a]aformat=channel_layouts=stereo,lowpass=f=140[kick]"
  filter << "[3:a]aformat=channel_layouts=stereo,highpass=f=900,lowpass=f=5000[snare]"
  filter << "[4:a]aformat=channel_layouts=stereo,highpass=f=6500[hats]"
  labels = %w[[ep] [bass] [kick] [snare] [hats]]
  weights = %w[1.00 0.80 0.72 0.55 0.24]

  if sample_index
    filter << "[#{sample_index}:a]aformat=channel_layouts=stereo,atrim=0:#{dur},asetpts=PTS-STARTPTS,highpass=f=70,lowpass=f=12000[sample]"
    labels << "[sample]"
    weights << "0.85"
  end

  filter << "#{labels.join}amix=inputs=#{labels.length}:weights=#{weights.join(' ')}:duration=first," \
            "acompressor=threshold=-18dB:ratio=2.4:attack=24:release=130," \
            "acrusher=bits=13:samples=2:mix=0.12," \
            "alimiter=limit=0.94:level_out=0.96[out]"

  cmd += ["-filter_complex", filter.join(";"), "-map", "[out]", "-t", dur.to_s, "-codec:a", "libmp3lame", "-b:a", "320k", dest]
  sh!(*cmd)
  puts "wrote #{dest}"
end

def verify(path = File.join(ROOT, "full_track.mp3"))
  abort "missing #{path}" unless File.exist?(path)
  out, err, ok = capture("ffmpeg", "-hide_banner", "-i", path, "-af", "volumedetect", "-f", "null", "-")
  text = out + err
  puts text.lines.grep(/Duration|bitrate|mean_volume|max_volume/).join
  abort "verify failed" unless ok && text.match?(/mean_volume:/)
end

def debug
  scan
  _out, err, ok = capture("ruby", "-c", __FILE__)
  puts(ok.success? ? "ruby syntax: ok" : err)
end

def sweep
  out = File.join(ROOT, "sweep_check.mp3")
  previous = ENV["BARS"]
  ENV["BARS"] = "8"
  render(out)
  verify(out)
ensure
  ENV["BARS"] = previous if previous
end

case ARGV.shift
when "scan" then scan
when "council" then council
when "sample" then sample
when "render", nil then render(ARGV.shift || File.join(ROOT, "full_track.mp3"))
when "verify" then verify(ARGV.shift || File.join(ROOT, "full_track.mp3"))
when "debug" then debug
when "sweep" then sweep
else
  puts "commands: scan | council | sample | render [out.mp3] | verify [out.mp3] | debug | sweep"
end
