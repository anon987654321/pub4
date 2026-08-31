# The loop played as an instrument, and the kit played as a record.
#
# "Make old things sound new, and new things sound old." Old to new: a slice of
# a 1970s bed is retriggered as chords the record never played -- asetrate is
# sampler pitching, speed and pitch together, which is what an MPC does and why
# chopped soul sounds like that. New to old: our own kit and the master go
# through the 1260 and the console, so nothing arrives clean.
#
# aevalsrc is avoided on long durations -- ruinously slow. One-shots are
# synthesised once, short, and placed with adelay, which costs nothing.
require "json"
require "time"
require "shellwords"

D = "/Users/mac/Documents/GitHub/pub4/STUDIO/dilla"

# Sonitex STX-1260 and Nasty VCS, as chains rather than as plugins. Multiple
# instances deliberately: one instance is a colour and three are a sound. The
# 1260 is the 12-bit sampler lineage -- bit reduction, a hard band limit, drive
# into that limit. VCS is a summing colour, applied wherever things are added,
# which is what a console does and why summed material glues.
def sonitex(bits:, lo:, hi:, drive:)
  "volume=#{drive},acrusher=bits=#{bits}:mode=log:aa=1," \
    "highpass=f=#{lo},lowpass=f=#{hi},alimiter=limit=0.99"
end

def vcs(depth:, smear:)
  # aphaser's delay floor is 0.1; under it nothing is audible and the knob only
  # appears to turn.
  # aphaser is not unity: in_gain and out_gain multiply, so 0.6 x 0.72 is a
  # 7dB cut per instance and three instances threw away 22dB before the limiter
  # ever saw the signal. Makeup here rather than at the master, so each console
  # stage stays level-neutral and the weights above mean what they say.
  "aphaser=in_gain=0.75:out_gain=0.85:delay=#{smear}:decay=#{depth}:speed=0.5," \
    "volume=1.9," \
    "aecho=0.9:0.25:#{smear.round}:0.08"
end

# Every pass is written down before it is heard. The rig was ephemeral once and
# a swept scratchpad took the takes with it -- the same defect that lost the
# crate: provenance living somewhere more fragile than what it describes.
def journal!(row)
  path = File.join(D, "project", "liveset.jsonl")
  File.open(path, File::WRONLY | File::APPEND | File::CREAT, 0o644) do |fh|
    fh.flock(File::LOCK_EX)
    fh.write("#{JSON.generate(row)}\n")
    fh.flush
  end
rescue StandardError
  nil # a journal that cannot write must not stop the music
end

FF = "/opt/homebrew/bin/ffmpeg"
Dir.chdir(D)

beds = Dir.glob("samples/chopped/*/loop.wav")
abort "no beds" if beds.empty?

# Least recently played, not random. Random repeats: with fifty racks it played
# the same four beds inside ten minutes, which reads as a short loop rather than
# as a crate. The journal already records what played and when, so it is also the
# play history -- one file, two jobs, no second source to drift.
played = Hash.new(0)
begin
  File.foreach(File.join(D, "project", "liveset.jsonl")).with_index do |line, i|
    slug = line[/"bed":"([^"]+)"/, 1]
    played[slug] = i if slug # later line wins: this is recency, not a count
  end
rescue StandardError
  nil
end
# Never-played beds sort first (-1), then oldest-played, and a little jitter so
# two racks cut from the same record do not always arrive back to back.
bed = beds.min_by { |b| [played.fetch(File.basename(File.dirname(b)), -1), rand] }
# 0.92-0.96: a semitone and a half down at the deep end. Never none.
DRAG = (0.92 + rand * 0.04).round(4)
slug = File.basename(File.dirname(bed))

# The grid comes from the record, not from a random number.
#
# chop cuts on bar lines, so a loop's duration is its tempo: one bar is the
# whole loop divided by however many bars it holds. The rack's loops.json only
# ever carries the last chop's entries, so the length is measured off the file
# instead -- ffprobe is the one reader that cannot go stale.
#
# And the drag moves the tempo with the pitch. asetrate slows the sample, so a
# bar that was T seconds is now T/DRAG, and a kit built on the undragged figure
# would run ahead of the record all night. This is what warping the drums to the
# flow of the sample actually means.
raw = `/opt/homebrew/bin/ffprobe -v quiet -show_entries format=duration -of csv=p=0 #{bed.shellescape}`.to_f
raw = 3.0 if raw <= 0.2
# Whole bars only, and the reading that lands in a tempo a human would count.
bars_in_loop = [1, 2, 4, 8].min_by do |b|
  implied = (b * 4 * 60.0) / (raw / DRAG)
  implied.between?(76, 104) ? (implied - 90).abs : 1_000 + (implied - 90).abs
end
bar   = ((raw / DRAG) / bars_in_loop).round(4)
beat  = (bar / 4).round(4)
step  = (beat / 2).round(4)   # eighths
sxt   = (beat / 4).round(4)   # sixteenths
bpm   = (60.0 / beat).round(1)
total = 96

# Voicings, not scale runs. Each step is a chord built from one slice: root,
# a colour tone and an extension, so the sample states harmony it never had.
# Downward only. Pitching a sample UP thins it and speeds it -- the chipmunk
# sound -- and nothing in this lineage does it. The same chords voiced BELOW the
# root instead: an octave down puts the colour tone under the fundamental, which
# is where a sampler lands when you play the pads left of centre. Every interval
# here is zero or negative, and the drag sits under all of it.
VOICINGS = {
  min7:  [0, -9, -2],    # root, b3 an octave down, b7 a tone below the root
  maj9:  [0, -8, -10],   # root, 3rd down an octave, 9th further under
  min9:  [0, -9, -10],
  sus4:  [0, -7, -2],
  min11: [0, -9, -7],
}.freeze
# Movement with rests in it. nil is a rest, and the rests are what make the
# rest of it read as playing.
# Roots move down too, or the phrase climbs out of the register the drag put it
# in. Nothing rises above the sample's own pitch.
PROGRESSIONS = [
  [[0, :min7], nil, [-5, :min9], [-3, :maj9], nil, [-2, :sus4], [0, :min7], nil],
  [[0, :min9], [-3, :min7], nil, [-7, :sus4], [-5, :maj9], nil, [-3, :min7], [0, :min11]],
  [[-7, :min7], nil, [-5, :min9], nil, [-3, :maj9], [0, :min7], nil, [-4, :sus4]],
  [[0, :min11], [0, :min11], nil, [-2, :maj9], [-3, :min7], nil, [-5, :min9], nil],
].freeze
prog = PROGRESSIONS.sample
slice_at = (rand * 2.2).round(3)
# 0.92-0.96: a semitone and a half down at the deep end, a third of one
# at the shallow. Never none.
reverse = rand < 0.28 # a reversed chop, sometimes

inputs = []
graph  = []
live   = []

prog.each_with_index do |cell, i|
  next if cell.nil?
  semi, voicing = cell
  ratios = VOICINGS.fetch(voicing).map { |iv| [((2.0**((semi + iv) / 12.0)) * DRAG), DRAG].min.round(6) }
  longest = (step * ratios.max * 1.8).round(4)
  inputs << "-ss #{slice_at} -t #{longest} -i #{bed.shellescape}"
  idx = inputs.size - 1
  graph << "[#{idx}:a]asplit=3[c#{i}a][c#{i}b][c#{i}c]"
  %w[a b c].each_with_index do |tag, v|
    rev = (reverse && v.zero?) ? "areverse," : ""
    graph << "[c#{i}#{tag}]asetrate=44100*#{ratios[v]},aresample=44100,#{rev}" \
             "atrim=0:#{step},volume=#{v.zero? ? 1.0 : 0.62}," \
             "afade=t=in:st=0:d=0.005,afade=t=out:st=#{(step - 0.03).round(4)}:d=0.03[v#{i}#{tag}]"
  end
  graph << "[v#{i}a][v#{i}b][v#{i}c]amix=inputs=3:normalize=0[ch#{i}]"
  live << i
end

# Rests are silence of exactly one step, so the phrase keeps the grid.
prog.each_index do |i|
  next if live.include?(i)
  inputs << "-f lavfi -t #{step} -i anullsrc=r=44100:cl=stereo"
  graph << "[#{inputs.size - 1}:a]atrim=0:#{step}[ch#{i}]"
end
graph << "#{prog.each_index.map { |i| "[ch#{i}]" }.join}concat=n=#{prog.size}:v=0:a=1," \
         "#{sonitex(bits: 12, lo: 90, hi: 9200, drive: 1.3)}," \
         "#{vcs(depth: 0.5, smear: 1.4)}," \
        "chorus=0.6:0.9:55:0.4:0.25:2," \
        "flanger=delay=4:depth=3:regen=22:speed=0.4," \
        "aecho=0.8:0.85:57|113:0.28|0.16," \
        "extrastereo=m=1.6[phrase]"

# Drunk drums. Dilla time is not a swing setting -- the kick and the snare drag
# in different directions and by different amounts, and the hats do not agree
# with either. Uniform swing sounds like a preset; this does not.
n = inputs.size
inputs << "-f lavfi -t 0.32 -i sine=f=52:d=0.32"
inputs << "-f lavfi -t 0.24 -i anoisesrc=c=pink:d=0.24"
inputs << "-f lavfi -t 0.05 -i anoisesrc=c=white:d=0.05"
inputs << "-f lavfi -t #{total} -i anoisesrc=c=pink:d=#{total}:a=0.006"
crackle_i = inputs.size - 1

jit = ->(ms) { (rand * ms * 2 - ms).round(1) }
kick_hits  = [0.0, (bar / 2 + step)].map { |t| [(t * 1000).round + jit.call(9), 0].max }
snare_hits = [beat, beat * 3].map { |t| (t * 1000).round + 22 + jit.call(7) }   # behind the grid
ghost_hits = [(beat * 2 + sxt), (beat * 3 + sxt * 3)].map { |t| (t * 1000).round + jit.call(14) }
hat_hits   = (0...8).map { |i| (i * step * 1000).round + (i.odd? ? 34 : 0) + jit.call(6) }

place = lambda do |idx, label, filt, hits|
  out = ["[#{idx}:a]#{filt}[#{label}_s]"]
  out << "[#{label}_s]asplit=#{hits.size}#{(0...hits.size).map { |k| "[#{label}x#{k}]" }.join}"
  # adelay refuses a negative delay, and the jitter that makes the drums drunk
  # can push a hit on the one below zero. Clamped here rather than at every call
  # site, so no future pattern can reintroduce it: the graph either builds or it
  # does not, and an intermittent failure is the worst kind.
  hits.each_with_index do |ms, k|
    d = [ms, 0].max.round
    out << "[#{label}x#{k}]adelay=#{d}|#{d}[#{label}p#{k}]"
  end
  out << "#{(0...hits.size).map { |k| "[#{label}p#{k}]" }.join}amix=inputs=#{hits.size}:normalize=0[#{label}]"
  out
end

graph += place.call(n, "kk", "volume=1.9,afade=t=out:st=0.015:d=0.24,lowpass=f=180,acrusher=bits=12:mode=log:aa=1", kick_hits)
graph += place.call(n + 1, "sn", "volume=1.5,afade=t=out:st=0.004:d=0.19,bandpass=f=1900:width_type=h:w=2600,volume=1.4", snare_hits)
graph += place.call(n + 2, "gh", "volume=0.24,afade=t=out:st=0.003:d=0.09,bandpass=f=2400:width_type=h:w=1800", ghost_hits)
graph += place.call(n + 3, "hh", "volume=0.26,afade=t=out:st=0.002:d=0.048,highpass=f=7200", hat_hits)

inputs << "-stream_loop -1 -i #{bed.shellescape}"
bed_i = inputs.size - 1
graph << "[#{bed_i}:a]asetrate=44100*#{DRAG},aresample=44100,atrim=0:#{(bar * bars_in_loop).round(4)}," \
                "volume=0.42,lowpass=f=5200,aecho=0.8:0.7:60:0.3," \
        "#{sonitex(bits: 13, lo: 60, hi: 7200, drive: 1.1)}," \
        "#{vcs(depth: 0.55, smear: 1.1)}[under]"

graph << "[kk][sn][gh][hh]amix=inputs=4:weights=2.8 2.4 1.1 1.0:normalize=0[kit_raw]"
graph << "[kit_raw]#{sonitex(bits: 11, lo: 42, hi: 12000, drive: 1.18)}," \
         "#{vcs(depth: 0.42, smear: 2.1)}[kit]"

graph << "[phrase][under][kit]amix=inputs=3:weights=0.30 0.14 3.4:" \
         "normalize=0:duration=longest," \
        "#{vcs(depth: 0.38, smear: 1.7)}," \
        "#{sonitex(bits: 12, lo: 40, hi: 13000, drive: 1.12)}," \
        "atrim=0:#{bar},asetpts=N/SR/TB[barmix]"

# Arrangement, not a loop on repeat: the phrase steps back for eight bars in the
# middle so the kit and the record carry it, then returns. A beat that never
# changes is a beat nobody listens to twice.
drop_from = (bar * 16).round(3)
drop_to   = (bar * 24).round(3)
graph << "[barmix]aloop=loop=-1:size=#{(bar * 44100).round},atrim=0:#{total}," \
         "volume='if(between(t,#{drop_from},#{drop_to}),0.55,1.0)':eval=frame," \
         "vibrato=f=1.7:d=0.14," \
         "acompressor=threshold=0.4:ratio=3.2:attack=9:release=210[body]"
graph << "[#{crackle_i}:a]highpass=f=2200,volume=0.9," \
                "#{vcs(depth: 0.6, smear: 0.9)}[crackle]"
graph << "[body][crackle]amix=inputs=2:weights=1 0.34:normalize=0:duration=first," \
         "#{vcs(depth: 0.34, smear: 2.4)}," \
         "#{sonitex(bits: 10, lo: 46, hi: 11500, drive: 1.1)}," \
         "#{vcs(depth: 0.26, smear: 3.6)}," \
         "aecho=0.85:0.7:83|151|229:0.20|0.12|0.06," \
         "tremolo=f=#{(2.0 / bar).round(3)}:d=0.10," \
         "treble=g=3:f=6500,bass=g=4:f=95," \
         "dynaudnorm=f=200:g=9:p=0.94:m=18," \
         "volume=2.4," \
         "alimiter=limit=0.98:level=disabled," \
         "aformat=sample_rates=44100:channel_layouts=stereo[out]"

journal!(
  at: Time.now.utc.iso8601, bed: slug, bpm: bpm, drag: DRAG, bars_in_loop: bars_in_loop, progression: prog,
  chop_at: slice_at, reversed: reverse, bar_s: bar,
  weights: { phrase: 0.52, under: 0.22, kit: 1.45 },
  drums: { kick_ms: kick_hits, snare_ms: snare_hits, ghost_ms: ghost_hits, hat_ms: hat_hits },
  sonitex: [13, 12, 12, 11, 10], vcs: 6, rig: "live/synth.rb"
)

cmd = "#{FF} -nostdin -loglevel error #{inputs.join(" ")} " \
      "-filter_complex #{graph.join("; ").shellescape} -map \"[out]\" -f wav -"
warn "▶ #{slug}  #{bpm}bpm (#{bars_in_loop}bar loop, drag #{DRAG})  #{prog.map { |c| c ? "#{c[0]}#{c[1]}" : "." }.join(" ")}" \
     "#{reverse ? "  REV" : ""}  chop@#{slice_at}s"
exec("/bin/zsh", "-c",
     "#{cmd} 2>/dev/null | /opt/homebrew/bin/ffplay -nodisp -autoexit -loglevel quiet -i - 2>/dev/null")
