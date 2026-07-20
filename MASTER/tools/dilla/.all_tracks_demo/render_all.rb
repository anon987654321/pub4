#!/usr/bin/env ruby
# frozen_string_literal: true

# Render every stream track and concat → demo.wav
# Usage: SPEAK=0 ruby .all_tracks_demo/render_all.rb [bars]

ROOT = File.expand_path("..", __dir__)
ENGINE = File.join(ROOT, "dilla.rb")
OUT_DIR = File.join(ROOT, ".all_tracks_demo")
FINAL = File.join(ROOT, "demo.wav")
BARS = (ARGV[0] || ENV["BARS"] || "12").to_i
LOG = File.join(OUT_DIR, "render_all.log")

require "fileutils"
require "open3"
require "shellwords"
require "rbconfig"

FileUtils.mkdir_p(OUT_DIR)

def log(msg)
  line = "#{Time.now.utc.strftime("%H:%M:%SZ")} #{msg}"
  puts line
  File.open(LOG, "a") { |f| f.puts(line) }
end

# Load engine only for track order + drum rotation helpers (no CLI dispatch).
$PROGRAM_NAME = "dilla_all_tracks_render"
load ENGINE

ENV["SPEAK"] ||= "0"
ENV["STREAM_CONTINUOUS"] = "0"
ENV["DILLA_STREAMING"] = "1"
ENV["DILLA_RAW"] = "0"
apply_best_defaults!
apply_dilla_style!(force: true)

order = stream_track_order
File.write(File.join(OUT_DIR, "order.txt"), order.map(&:to_s).join("\n") + "\n")
log "tracks=#{order.length} bars=#{BARS} → #{FINAL}"

parts = []
order.each_with_index do |track, idx|
  slug = track.to_s
  part = File.join(OUT_DIR, format("%02d_%s.wav", idx, slug))
  if File.file?(part) && File.size(part) > 100_000
    log "skip existing #{File.basename(part)} (#{File.size(part)} bytes)"
    parts << part
    next
  end

  # Fresh ENV DNA per track (isolate shell ENV pollution).
  env = ENV.to_h.merge(
    "TRACK" => slug,
    "PROGRESSION" => slug,
    "SPEAK" => ENV.fetch("SPEAK", "0"),
    "DILLA_STREAMING" => "1",
    "STREAM_CONTINUOUS" => "0",
    "BARS" => BARS.to_s
  )
  # Drum rotation mirrors stream
  d = STREAM_DRUM_ROTATION[idx % STREAM_DRUM_ROTATION.length]
  env["DRUM_PRESET"] = d[:preset]
  env["POCKET_SET"] = d[:pocket]
  env["EXTERNAL_KIT"] = d[:kit] if d[:kit] && !d[:kit].empty?
  env["FM_DRUMS"] = d[:fm] if d[:fm]
  env["FLYLO_DRUM_OVERLAY"] = d[:flylo] || "0"

  log "render #{idx + 1}/#{order.length} #{slug} drums=#{d[:preset]}/#{d[:pocket]}"
  cmd = [RbConfig.ruby, ENGINE, "dilla", part, BARS.to_s, "--track=#{slug}"]
  out, err, st = Open3.capture3(env, *cmd)
  File.open(LOG, "a") do |f|
    f.puts out.to_s.lines.last(5).join
    f.puts err.to_s.lines.last(8).join unless err.to_s.empty?
  end
  unless st.success? && File.file?(part) && File.size(part) > 50_000
    log "FAIL #{slug} status=#{st.exitstatus} size=#{File.file?(part) ? File.size(part) : 0}"
    # Retry once without rap (common hang/fail path)
    env["RAP_VOCAL"] = "0"
    out2, err2, st2 = Open3.capture3(env, *cmd)
    File.open(LOG, "a") { |f| f.puts out2.to_s.lines.last(3).join; f.puts err2.to_s.lines.last(5).join }
    unless st2.success? && File.file?(part) && File.size(part) > 50_000
      log "SKIP after retry: #{slug}"
      next
    end
  end
  log "ok #{slug} #{(File.size(part) / 1_000_000.0).round(2)}MB"
  parts << part
  # Drop engine scratch between tracks to free disk
  Dir.glob(File.join(ROOT, ".dilla_*.{wav,mid}")).each { |p| FileUtils.rm_f(p) }
  Dir.glob(File.join(ROOT, ".dilla_*.wav.*")).each { |p| FileUtils.rm_f(p) }
end

if parts.empty?
  log "no parts rendered — abort"
  exit 1
end

list = File.join(OUT_DIR, "concat.txt")
File.write(list, parts.map { |p| "file '#{p}'" }.join("\n") + "\n")
tmp = File.join(OUT_DIR, "demo_concat.wav")
log "concat #{parts.length} parts → demo.wav"
ok = system("ffmpeg", "-y", "-f", "concat", "-safe", "0", "-i", list,
            "-c", "copy", tmp)
unless ok && File.file?(tmp)
  # re-encode fallback if codecs differ
  log "concat copy failed — re-encode"
  ok = system("ffmpeg", "-y", "-f", "concat", "-safe", "0", "-i", list,
              "-ar", "44100", "-ac", "2", "-c:a", "pcm_s16le", tmp)
end
abort "concat failed" unless ok && File.file?(tmp)

FileUtils.mv(tmp, FINAL)
dur = `ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 #{Shellwords.escape(FINAL)} 2>/dev/null`.to_f
log "wrote #{FINAL} parts=#{parts.length}/#{order.length} size=#{(File.size(FINAL) / 1_000_000.0).round(2)}MB duration=#{dur.round(1)}s"
puts "ok: #{FINAL} (#{parts.length} tracks, #{dur.round(1)}s)"
