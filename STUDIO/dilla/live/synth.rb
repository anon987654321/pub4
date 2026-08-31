# The loop played as a synth, and the kit played as a record.
#
# "Make old things sound new, and new things sound old." Both halves are here.
# Old to new: a slice of the 1970s bed is retriggered at intervals the record
# never played -- asetrate is sampler pitching, speed and pitch together, which
# is what an MPC does and why chopped soul sounds like that. New to old: our own
# kit and the master go through the 1260 and the console, so nothing arrives
# clean.
#
# aevalsrc is avoided on long durations -- it is ruinously slow. One-shots are
# synthesised once, short, then placed with adelay, which costs nothing.
require "json"
require "time"
require "shellwords"

# Sonitex STX-1260 and Nasty VCS, as chains rather than as plugins.
#
# Multiple instances, deliberately: one instance is a colour and three are a
# sound. The 1260 is the 12-bit sampler lineage -- bit reduction, a hard band
# limit, drive into that limit -- so it sits on the chopped phrase where the
# sampler would have been, again on the drum bus, and gentler on the master.
# VCS is a summing colour rather than an effect: phase smear and saturation at
# every point where things are added, which is what a console does and why
# summed material glues instead of layering.
def sonitex(bits:, lo:, hi:, drive:)
  "volume=#{drive},acrusher=bits=#{bits}:mode=log:aa=1," \
    "highpass=f=#{lo},lowpass=f=#{hi},alimiter=limit=0.97"
end

def vcs(depth:, smear:)
  # aphaser's delay floor is 0.1; under it nothing is audible and the knob only
  # appears to turn. Kept above, with a very short echo so the smear reads as
  # phase rather than as a repeat.
  "aphaser=in_gain=0.6:out_gain=0.72:delay=#{smear}:decay=#{depth}:speed=0.5," \
    "aecho=0.9:0.25:#{smear.round}:0.08"
end


# Every pass is written down before it is heard.
#
# The live rig was ephemeral: bed, chop point, phrase, tempo and mix existed
# only in a scratchpad log, and on 2026-08-31 the scratchpad swept the rig
# itself away mid-session. A take nobody recorded is a take nobody can play
# again, which is the same defect that lost the crate -- provenance living
# somewhere more fragile than the thing it describes.
#
# One line per pass, appended under an exclusive lock and flushed before the
# lock drops. A single short line is written atomically, so a kill mid-session
# truncates nothing and the journal is always valid JSONL.
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

D = "/Users/mac/Documents/GitHub/pub4/STUDIO/dilla"
FF = "/opt/homebrew/bin/ffmpeg"
Dir.chdir(D)

beds = Dir.glob("samples/chopped/*/loop.wav")
abort "no beds" if beds.empty?
bed = beds.sample
slug = File.basename(File.dirname(bed))

bpm  = 86 + rand(12)
beat = (60.0 / bpm).round(4)
step = (beat / 2).round(4)
bar  = (beat * 4).round(4)
late = 0.026 # Dilla time: the backbeat drags behind the grid

PHRASES = [
  [0, 3, 5, 7, 5, 3, 0, -2],
  [0, 5, 3, 7, 10, 7, 5, 3],
  [0, -2, 3, 5, 3, 0, -4, 0],
  [7, 5, 3, 0, 3, 5, 7, 10],
].freeze
phrase = PHRASES.sample
slice_at = (rand * 2.0).round(3)

inputs = []
graph  = []
phrase.each_with_index do |semi, i|
  ratio = (2.0**(semi / 12.0)).round(6)
  inputs << "-ss #{slice_at} -t #{(step * ratio * 1.6).round(4)} -i #{bed.shellescape}"
  graph << "[#{i}:a]asetrate=44100*#{ratio},aresample=44100,atrim=0:#{step}," \
           "afade=t=in:st=0:d=0.004,afade=t=out:st=#{(step - 0.02).round(4)}:d=0.02[s#{i}]"
end
tags = (0...phrase.size).map { |i| "[s#{i}]" }.join
graph << "#{tags}concat=n=#{phrase.size}:v=0:a=1," \
         "#{sonitex(bits: 12, lo: 90, hi: 9500, drive: 1.25)}," \
         "#{vcs(depth: 0.5, smear: 1.4)}[phrase]"

n = inputs.size
inputs << "-f lavfi -t 0.30 -i sine=f=54:d=0.30"
inputs << "-f lavfi -t 0.22 -i anoisesrc=c=pink:d=0.22"
inputs << "-f lavfi -t 0.06 -i anoisesrc=c=white:d=0.06"

place = lambda do |idx, label, filt, hits|
  out = ["[#{idx}:a]#{filt}[#{label}_src]"]
  out << "[#{label}_src]asplit=#{hits.size}#{(0...hits.size).map { |k| "[#{label}s#{k}]" }.join}"
  hits.each_with_index do |t, k|
    ms = (t * 1000).round
    out << "[#{label}s#{k}]adelay=#{ms}|#{ms}[#{label}p#{k}]"
  end
  out << "#{(0...hits.size).map { |k| "[#{label}p#{k}]" }.join}" \
         "amix=inputs=#{hits.size}:normalize=0[#{label}]"
  out
end

graph += place.call(n, "k", "volume=1.4,afade=t=out:st=0.02:d=0.26,lowpass=f=95",
                    [0.0, (bar / 2 + step).round(4)])
graph += place.call(n + 1, "sn", "volume=0.9,afade=t=out:st=0.005:d=0.2,bandpass=f=1800:width_type=h:w=1500",
                    [(beat + late).round(4), (beat * 3 + late).round(4)])
graph += place.call(n + 2, "h", "volume=0.30,afade=t=out:st=0.002:d=0.055,highpass=f=7000",
                    (0...8).map { |i| (i * step).round(4) })

inputs << "-stream_loop -1 -i #{bed.shellescape}"
bed_i = inputs.size - 1
graph << "[#{bed_i}:a]atrim=0:#{bar},volume=0.30,lowpass=f=6000[under]"

# Drum bus: summed, then the second 1260 and the second console.
graph << "[k][sn][h]amix=inputs=3:weights=1.6 1.25 0.72:normalize=0[kit_raw]"
graph << "[kit_raw]#{sonitex(bits: 11, lo: 42, hi: 12000, drive: 1.15)}," \
         "#{vcs(depth: 0.42, smear: 2.1)}[kit]"

# Drums forward, record back: the sample is the bed, not the lead.
graph << "[phrase][under][kit]amix=inputs=3:weights=0.50 0.22 1.45:" \
         "normalize=0:duration=longest,atrim=0:#{bar},asetpts=N/SR/TB[barmix]"

graph << "[barmix]aloop=loop=-1:size=#{(bar * 44100).round},atrim=0:96," \
         "vibrato=f=1.7:d=0.13," \
         "acompressor=threshold=0.4:ratio=3.2:attack=9:release=210," \
         "#{sonitex(bits: 10, lo: 46, hi: 11000, drive: 1.06)}," \
         "#{vcs(depth: 0.3, smear: 3.0)}," \
         "alimiter=limit=0.94,aformat=sample_rates=44100:channel_layouts=stereo[out]"

cmd = "#{FF} -nostdin -loglevel error #{inputs.join(" ")} " \
      "-filter_complex #{graph.join("; ").shellescape} -map \"[out]\" -f wav -"
journal!(
  at: Time.now.utc.iso8601, bed: slug, bpm: bpm, phrase: phrase,
  chop_at: slice_at, bar_s: bar, late_s: late,
  weights: { phrase: 0.50, under: 0.22, kit: 1.45 },
  sonitex: [12, 11, 10], vcs: 3, rig: "live/synth.rb"
)
warn "▶ #{slug}  #{bpm}bpm  phrase=#{phrase.join(",")}  chop@#{slice_at}s  " \
     "sonitex=12/11/10bit vcs=x3"
exec("/bin/zsh", "-c",
     "#{cmd} 2>/dev/null | /opt/homebrew/bin/ffplay -nodisp -autoexit -loglevel quiet -i - 2>/dev/null")
