# frozen_string_literal: true

# The FUCK_YOUR_XBOX remix driver: the operator's own track, slowed and demuxed,
# every stem through dilla's own grade racks, then remixed and mastered.
#
# Golden rule honoured: atempo (time-stretch, pitch preserved), never varispeed.
# Reproduce with: ruby xbox_remix.rb  (then wait for demo.wav, run combine step)

require "json"
require "fileutils"

DILLA = File.expand_path(__dir__)
REPO = File.expand_path("../..", DILLA)
RUBY34 = File.join(REPO, "MASTER", "bin", "ruby")
SCRATCH = File.join(DILLA, "scratch", "xbox_remix")
SLOW = 0.80 # 39.1s -> 48.88s is the ratio the earlier slowed stems used

def sh!(*args)
  puts "$ #{args.join(' ')}"
  out, status = Open3.capture2e(*args)
  puts out
  abort "command failed: #{args.first}" unless status.success?
end

require "open3"

def fx(input, output, chain)
  sh! "ffmpeg", "-y", "-i", input, "-af", chain, "-c:a", "pcm_s16le", output
end

FileUtils.mkdir_p(SCRATCH)
Dir.chdir(DILLA)

master = File.join(DILLA, "FUCK_YOUR_XBOX.mp3")
FileUtils.cp(File.join(REPO, "MASTER", "YES.mp3"), master) unless File.exist?(master)
abort "missing #{master}" unless File.exist?(master)

# 1. Slow the whole master: atempo keeps the pitch, changes only the pace.
slowed = File.join(SCRATCH, "slowed_master.wav")
fx master, slowed, "atempo=#{SLOW}"

# 2. Demux the slowed master through dilla's own separation pipeline.
# Demux output is samples/demux/<model>/<basename> (demux_six joins DEMUX_DIR,
# "demux" -- DEMUX_DIR is already samples/demux). Skip if stems are cached.
stem_dir = File.join(DILLA, "samples", "demux", "htdemucs_6s", "slowed_master")
sh! RUBY34, "dilla.rb", "demux", slowed unless Dir.exist?(stem_dir)
abort "demux produced no stems at #{stem_dir}" unless Dir.exist?(stem_dir)

# 3. Per-stem effects. `grade` runs dilla's own grade_filter code, so the
# presets below are the engine's, not a reimplementation.
treated = {}
{
  "drums" => ["sp1200", "transient recovery under the saturation"],
  "bass" => ["tape_hot", "fundamental forward"],
  "vocals" => ["tape_warm", "slapback echo — the echo is not optional"],
  "guitar" => ["sonitex", ""],
  "piano" => ["vinyl_lab", ""],
  "other" => ["dub_chamber", ""],
}.each do |stem, (preset, _note)|
  src = File.join(stem_dir, "#{stem}.wav")
  abort "missing stem #{src}" unless File.exist?(src)
  graded = File.join(SCRATCH, "#{stem}_graded.wav")
  sh! RUBY34, "dilla.rb", "grade", src, graded, preset
  treated[stem] = graded
end

# 4. The per-stem finishing chains the presets do not carry.
# Drums: the transient recovery from commit 374f35484 — slowed drums lose their
# attack, so a highpassed, compressed copy rides back in at 30%.
drums_out = File.join(SCRATCH, "drums_final.wav")
sh! "ffmpeg", "-y", "-i", treated["drums"],
    "-filter_complex",
    "[0:a]highpass=f=2000,acompressor=attack=1:release=50:ratio=4:threshold=-20dB,highshelf=f=5000:g=6[r];" \
    "[0:a][r]amix=inputs=2:weights=1 0.3:normalize=0:duration=first[out]",
    "-map", "[out]", "-c:a", "pcm_s16le", drums_out
treated["drums"] = drums_out

# Bass: fundamental emphasised, per dc533bdc3.
bass_out = File.join(SCRATCH, "bass_final.wav")
fx treated["bass"], bass_out, "lowshelf=f=90:g=4dB,highpass=f=35"
treated["bass"] = bass_out

# Vocals: upfront first, then the slapback and a light chorus behind them.
vocals_out = File.join(SCRATCH, "vocals_final.wav")
fx treated["vocals"], vocals_out,
    "acompressor=threshold=-18dB:ratio=3:attack=5:release=120:makeup=2," \
    "aecho=0.8:0.25:120:0.3,chorus=0.5:0.9:50|60:0.4|0.32:0.25|0.4:2|1.3"
treated["vocals"] = vocals_out

# 5. Dust: the record surface the slowed aesthetic lives on.
length = `ffprobe -v error -show_entries format=duration -of csv=p=0 #{slowed}`.strip.to_f
dust = File.join(SCRATCH, "dust.wav")
sh! "ffmpeg", "-y",
    "-f", "lavfi", "-i", "anoisesrc=color=pink:amplitude=0.004:duration=#{length.round}",
    "-af", "highpass=f=300,lowpass=f=3500,volume=-32dB,afade=t=in:d=3," \
           "afade=t=out:st=#{(length - 4).round}:d=4",
    "-c:a", "pcm_s16le", dust

# 6. The mix: stems weighted, then the dilla master target: -14 LUFS, -1 dBTP.
remix = File.join(DILLA, "FUCK_YOUR_XBOX_slowed_remix.wav")
weights = { "drums" => 1.0, "bass" => 1.0, "vocals" => 1.15,
            "guitar" => 0.75, "piano" => 0.85, "other" => 0.7 }
inputs = weights.keys.map { |stem| ["-i", treated[stem]] }.flatten + ["-i", dust]
n = weights.size + 1
mix_chain = "#{(0...n).map { |i| "[#{i}:a]" }.join}" \
            "amix=inputs=#{n}:weights=#{weights.values.join(' ')} 0.04:" \
            "normalize=0:duration=longest," \
            "acompressor=threshold=-18dB:ratio=2:attack=8:release=120:makeup=2," \
            "loudnorm=I=-14:TP=-1.0:LRA=11,alimiter=limit=0.98[out]"
sh! "ffmpeg", "-y", *inputs, "-filter_complex", mix_chain, "-map", "[out]",
    "-c:a", "pcm_s16le", remix

remix_mp3 = remix.sub(/\.wav\z/, ".mp3")
sh! "ffmpeg", "-y", "-i", remix, "-c:a", "libmp3lame", "-b:a", "320k", remix_mp3

recipe = {
  schema: "dilla.remix.v1",
  track: "FUCK_YOUR_XBOX",
  slow_factor: SLOW,
  stretch: "atempo (pitch preserved — never varispeed)",
  demux_model: "htdemucs_6s",
  stems: weights,
  grade_presets: { drums: "sp1200", bass: "tape_hot", vocals: "tape_warm",
                   guitar: "sonitex", piano: "vinyl_lab", other: "dub_chamber" },
  extra: ["drums transient recovery 30% (374f35484)", "bass fundamental +4dB at 90Hz",
          "vocals slapback 120ms + light chorus", "pink-noise dust bed at -32dB"],
  master: "bus comp, loudnorm I=-14 TP=-1.0, limiter 0.98",
  reproduce: "ruby xbox_remix.rb from STUDIO/dilla",
  rendered_at: Time.now.strftime("%Y-%m-%d %H:%M"),
}
File.write("#{remix}.provenance.json", JSON.pretty_generate(recipe) + "\n")
puts "remix done: #{remix}"

# 7. The combine step waits for the fresh demo.wav, then crossfades into it.
demo = File.join(DILLA, "demo.wav")
tries = 0
until File.exist?(demo) || tries >= 240
  tries += 1
  sleep 5
end
if File.exist?(demo)
  combined = File.join(DILLA, "FUCK_YOUR_XBOX_remix_into_demo.wav")
  sh! "ffmpeg", "-y", "-i", remix, "-i", demo,
      "-filter_complex", "acrossfade=d=2:c1=tri:c2=tri[out]",
      "-map", "[out]", "-c:a", "pcm_s16le", combined
  sh! "ffmpeg", "-y", "-i", combined, "-c:a", "libmp3lame", "-b:a", "320k",
      combined.sub(/\.wav\z/, ".mp3")
  puts "combined done: #{combined}"
else
  puts "demo.wav never appeared; skipping the combine step"
end