# demo.mp3 is the livestream, recorded.
#
# There is no separate demo render any more. A second render path is a second
# thing to keep in step with the first, and it drifted within an hour of being
# written -- the demo was rendering one chain while the speakers played another.
# The generator already produces exactly this sound; this joins its output into
# one continuous file and encodes it.
require "fileutils"

BASE = "/Users/mac/Music/dilla_sines"
ARCHIVE = File.join(BASE, "archive")
TARGET = (ENV["DEMO_SECS"] || "600").to_f
OUT = ENV["DEMO_OUT"] || File.join(BASE, "demo.mp3")
RATE = 44_100

def read_wav_pcm(path)
  raw = File.binread(path)
  return nil unless raw[0, 4] == "RIFF"

  pos = 12
  data = nil
  fmt = nil
  while pos + 8 <= raw.bytesize
    id = raw[pos, 4]
    sz = raw[pos + 4, 4].unpack1("V")
    fmt = raw[pos + 8, sz] if id == "fmt "
    data = raw[pos + 8, sz] if id == "data"
    pos += 8 + sz + (sz.odd? ? 1 : 0)
  end
  return nil unless data && fmt && fmt[14, 2].unpack1("v") == 16

  data
end

files = Dir[File.join(ARCHIVE, "*.wav")].sort
abort "  nothing in the archive yet" if files.empty?

need_bytes = (TARGET * RATE * 4).to_i
chunks = []
have = 0
files.cycle do |f|
  break if have >= need_bytes

  pcm = read_wav_pcm(f)
  next unless pcm

  chunks << pcm
  have += pcm.bytesize
  break if chunks.length > 400
end
abort "  no readable audio" if chunks.empty?

body = chunks.join[0, need_bytes]
wav = File.join(BASE, "demo_build.wav")
File.open(wav, "wb") do |o|
  o.write("RIFF"); o.write([36 + body.bytesize].pack("V")); o.write("WAVEfmt ")
  o.write([16, 1, 2, RATE, RATE * 4, 4, 16].pack("Vv v V V v v"))
  o.write("data"); o.write([body.bytesize].pack("V"))
  o.write(body)
end
ok = system("/opt/homebrew/bin/ffmpeg", "-y", "-i", wav, "-codec:a", "libmp3lame",
            "-b:a", "320k", OUT, out: File::NULL, err: File::NULL)
FileUtils.rm_f(wav)
abort "  ffmpeg failed" unless ok && File.file?(OUT)

mins = (body.bytesize / 4.0 / RATE / 60).round(1)
puts format("  wrote %s  %.1fMB  %s min  from %d stream takes", OUT, File.size(OUT) / 1e6, mins, chunks.length)
