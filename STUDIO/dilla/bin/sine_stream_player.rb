# Drains the generator's queue. Never replays a verse.
#
# The rule is that a rap vocal is never heard twice, and generation has honoured
# it since the used-list went in -- but playback did not. When the queue ran dry
# this replayed an archived take at random, vocal and all, so the same verse came
# round again through no fault of the generator. Buffering deeper only made it
# rarer, which is not what "never" means.
#
# Now: a take that carried a vocal is played once and never again. Only
# instrumental takes are eligible for replay, and when there are none the
# heartbeat carries it alone -- which is the instruction, better to shut up.
require "fileutils"

BASE = "/Users/mac/Music/dilla_sines"
Q = File.join(BASE, "q")
ARCHIVE = File.join(BASE, "archive")
STOP = File.join(BASE, "STOP")
NOW = File.join(BASE, "now_playing.txt")
VOICES = %w[store_p gunnhild jonas_v].freeze
KEEP = 60

FileUtils.mkdir_p(ARCHIVE)

def has_vocal?(wav)
  txt = wav.sub(/\.wav\z/, ".txt")
  return true unless File.file?(txt) # unknown provenance is treated as vocal

  line = File.read(txt)
  VOICES.any? { |v| line.include?("+#{v}") }
end

last = nil
until File.exist?(STOP)
  fresh = Dir[File.join(Q, "[0-9]*.wav")].sort.first
  if fresh && File.size(fresh) > 100_000
    txt = fresh.sub(/\.wav\z/, ".txt")
    File.write(NOW, File.read(txt)) if File.file?(txt)
    system("/usr/bin/afplay", fresh)
    # The sidecar travels with the take, so the archive knows which ones carry a
    # verse and are therefore spent.
    FileUtils.mv(fresh, ARCHIVE, force: true) rescue nil
    FileUtils.mv(txt, ARCHIVE, force: true) if File.file?(txt)
    old = Dir[File.join(ARCHIVE, "*.wav")].sort_by { |f| -File.mtime(f).to_i }[KEEP..]
    Array(old).each { |f| FileUtils.rm_f(f); FileUtils.rm_f(f.sub(/\.wav\z/, ".txt")) }
    next
  end

  pool = Dir[File.join(ARCHIVE, "*.wav")].reject { |f| has_vocal?(f) }
  if pool.any?
    pick = pool.sample
    pick = (pool - [last]).sample || pick if pick == last && pool.length > 1
    last = pick
    File.write(NOW, "replay (instrumental) #{File.basename(pick)}\n")
    system("/usr/bin/afplay", pick)
  else
    # Nothing new and nothing without a verse on it. The heartbeat holds the
    # room rather than a repeated bar doing it.
    File.write(NOW, "waiting — no unheard take, and no instrumental to replay\n")
    sleep 4
  end
end
