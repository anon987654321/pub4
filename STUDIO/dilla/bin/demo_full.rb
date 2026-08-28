# demo.mp3: the full showcase.
#
# Walks the progression catalogue with every synth stack and every Detroit feel
# in rotation, each progression getting its own random drum chain, its own
# bassline drawn from its own chords, and a vocal that is never heard twice.
# One pass of the master chain over the whole thing at the end, so the record is
# mastered as a record rather than take by take.
Dir.chdir("/Users/mac/Documents/GitHub/pub4/STUDIO/dilla")
src = File.read("/Users/mac/Music/dilla_sines/sine_stream.rb")
eval(src.split("cfg = dilla_resolve_config").first) # rubocop:disable Security/Eval
require "fileutils"

$stdout.sync = true
TARGET = (ENV["DEMO_SECS"] || "600").to_f
# Deliberately not called OUT. sine_stream.rb defines OUT as the DIRECTORY that
# master_chain! writes its temporary wavs into, and redefining it here as a file
# path meant ten minutes of finished rendering died at the very last step,
# trying to open a file inside demo.mp3/. Ruby warned about the reinitialised
# constant and the warning went by in a log nobody was reading.
DEMO_MP3 = "/Users/mac/Music/dilla_sines/demo.mp3"
cfg = dilla_resolve_config
xf = (RATE * 0.6).to_i

# Spread across the catalogue rather than taking the first thirty: the demo is
# meant to show the range, and the first thirty keys are alphabetical accident.
all = CHORD_PROGRESSIONS.keys
names = all.each_slice([all.length / 40, 1].max).map(&:first)
stacks = PAD_STACKS

l = []; r = []; voc_l = []; voc_r = []; log = []
names.each_with_index do |name, ni|
  break if l.length >= RATE * TARGET

  pads = begin
    p0 = dilla_progression(name)
    next if p0.nil? || p0.empty?

    p1, = DillaHarmony.beautify_pipeline(p0, cfg.merge(progression: name))
    (p1 && !p1.empty? ? p1 : p0)
  rescue StandardError
    next
  end
  flow = flow_shape(ni)
  pads = pads.first(flow[:chords])
  stack = stacks[(ni * 3) % stacks.length]
  ENV["PAD_VOICE"] = stack.to_s
  ev = pads.each_with_index.map { |c, i| [i * SECS, 0.85, c, SECS * 1.02] }
  tmp = "/Users/mac/Music/dilla_sines/df_pad.wav"
  pl = []; pr = []
  begin
    render_pad_via_fluidsynth(tmp, ev, pads.length * SECS)
    got = File.file?(tmp) ? read_wav(tmp) : nil
    pl, pr = got[0], got[1] if got
  rescue StandardError
    nil
  ensure
    FileUtils.rm_f(tmp)
  end
  next if pl.empty?

  dl = Array.new(pl.length, 0.0); dr = Array.new(pr.length, 0.0)
  feel = nil
  pads.each_index { |b| feel = drums_for_bar!(dl, dr, (b * SECS * RATE).to_i, SECS, ni * 4 + b) }
  used = drum_chain!(dl, dr, ni * 977 + 7)
  tame_transients!(dl, dr)
  level_drums!(dl, dr, pl, pr)

  bl = Array.new(pl.length, 0.0); br = Array.new(pr.length, 0.0)
  pads.each_with_index do |c, b|
    at = (b * SECS * RATE).to_i
    bass_line!(bl, br, c, pads[b + 1], at, SECS, ni * 4 + b)
    duck_bass_under_kick!(bl, br, at, SECS, ni * 4 + b)
  end
  tame_transients!(bl, br, over_db: 6.0)
  level_drums!(bl, br, pl, pr)
  dl.length.times { |i| pl[i] += dl[i] + bl[i]; pr[i] += dr[i] + br[i] }

  case flow[:depth]
  when 0.85..1.0
    copy_machine!(pl, pr, copies: 5, reverse: 0.4, width: 1.0)
    space_echo!(pl, pr, time_s: SECS / 5.0, feedback: 0.5, heads: 3, mix: 0.3)
    ring_mod!(pl, pr, hz: 61.0, drift_hz: 0.23, mix: 0.18)
  when 0.5...0.85
    space_echo!(pl, pr, time_s: SECS / 6.0, feedback: 0.5, heads: 3, mix: 0.25)
  end
  artifacts!(pl, pr, seed: ni * 101, count: flow[:artifacts]) if flow[:artifacts].positive?
  barber_phaser!(pl, pr, rate_hz: 0.04 + flow[:depth] * 0.09,
                         depth: 0.35 + flow[:depth] * 0.4, mix: 0.14 + flow[:depth] * 0.26)

  sl = Array.new(pl.length, 0.0); sr = Array.new(pr.length, 0.0)
  slug = ni % 3 == 2 ? VOCAL_TAIL : VOCAL_LEAD
  voiced = add_vocal!(sl, sr, slug, 1.0, ni, gain: 1.0)
  vocal_chain!(sl, sr) if voiced
  at = [l.length - xf, 0].max
  (voc_l.length...(at + sl.length)).each { voc_l << 0.0; voc_r << 0.0 }
  sl.each_index { |i| voc_l[at + i] += sl[i]; voc_r[at + i] += sr[i] }

  cassette!(pl, pr)
  crossfade_append!(l, r, pl, pr, xf)
  log << "#{name}|#{stack}|#{feel}|#{used.join('-')}|#{voiced ? slug : 'inst'}|~#{(flow[:depth] * 100).round}"
  puts format("  %3d  %6.1fs  %s", ni + 1, l.length.to_f / RATE, log.last[0, 92])
end
abort "  nothing rendered" if l.empty?

puts format("  mastering %.1f min ...", l.length.to_f / RATE / 60)
master_chain!(l, r)
n = [l.length, voc_l.length].min
n.times { |i| l[i] += voc_l[i] * 0.26; r[i] += voc_r[i] * 0.26 }
soft_limit!(l, r, ceiling: 0.94)
edge = (RATE * 2.0).to_i
edge.times do |i|
  g = i.to_f / edge
  l[i] *= g; r[i] *= g
  l[-1 - i] *= g; r[-1 - i] *= g
end
wav = "/Users/mac/Music/dilla_sines/demo_full.wav"
write_wav(wav, l, r)
system("/opt/homebrew/bin/ffmpeg", "-y", "-i", wav, "-codec:a", "libmp3lame", "-b:a", "320k",
       DEMO_MP3, out: File::NULL, err: File::NULL)
FileUtils.rm_f(wav)
File.write(DEMO_MP3.sub(/\.mp3\z/, ".tracklist.txt"), log.join("\n") + "\n")
puts format("  wrote %s  %.1fMB  %.1f min  %d progressions",
            DEMO_MP3, File.size(DEMO_MP3) / 1e6, l.length.to_f / RATE / 60, log.size)
