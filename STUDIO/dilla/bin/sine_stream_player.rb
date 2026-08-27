# Drains the generator's queue, and never leaves the speakers empty.
#
# Played files move to archive/ rather than being deleted, because generation --
# fluidsynth per pad layer, then four full master passes -- runs slower than
# playback, and the honest answer to "the queue is empty" is to put on a take
# from earlier rather than a tick. A tick is a heartbeat, not entertainment.
require "fileutils"

BASE = "/Users/mac/Music/dilla_sines"
Q = File.join(BASE, "q")
ARCHIVE = File.join(BASE, "archive")
STOP = File.join(BASE, "STOP")
TICK = File.join(BASE, "tick.wav")
NOW = File.join(BASE, "now_playing.txt")
KEEP = 40

FileUtils.mkdir_p(ARCHIVE)
last = nil

until File.exist?(STOP)
  fresh = Dir[File.join(Q, "[0-9]*.wav")].sort.first
  if fresh && File.size(fresh) > 100_000
    txt = fresh.sub(/\.wav\z/, ".txt")
    File.write(NOW, File.read(txt)) if File.file?(txt)
    system("/usr/bin/afplay", fresh)
    FileUtils.mv(fresh, ARCHIVE, force: true) rescue nil
    FileUtils.rm_f(txt)
    old = Dir[File.join(ARCHIVE, "*.wav")].sort_by { |f| -File.mtime(f).to_i }[KEEP..]
    Array(old).each { |f| FileUtils.rm_f(f) }
    next
  end

  pool = Dir[File.join(ARCHIVE, "*.wav")]
  if pool.any?
    pick = pool.sample
    pick = (pool - [last]).sample || pick if pick == last && pool.length > 1
    last = pick
    File.write(NOW, "replay #{File.basename(pick)} — generator still building\n")
    system("/usr/bin/afplay", pick)
  else
    system("/usr/bin/afplay", TICK) if File.file?(TICK)
    sleep 2
  end
end
