#!/usr/bin/env ruby
# frozen_string_literal: true

# Play extracted liveset MIDI two ways at once: fluidsynth (GM) and
# AnalogSynth (Moog ladder). Notes in the GM drum range (35-59) are copied
# into the hiphop midi crate, not voiced as pitches.
require "fileutils"
require "stringio"
require_relative "lib/sound"

RATE = 44_100
DRUM_LO = 35
DRUM_HI = 59
SF = "/opt/homebrew/Cellar/fluid-synth/2.5.6/share/fluid-synth/sf2/VintageDreamsWaves-v2.sf2"
CRATE = File.join(__dir__, "samples", "midi")
MID_DIR = File.join(__dir__, "livesets_midi")

def read_vlq(io)
  n = 0
  loop do
    b = io.readbyte
    n = (n << 7) | (b & 0x7f)
    break if b < 0x80
  end
  n
end

def parse_mid(path)
  data = File.binread(path)
  io = StringIO.new(data)
  io.read(4)
  io.read(4)
  _fmt, _ntr, ppq = io.read(6).unpack("n*")
  io.read(4)
  tlen = io.read(4).unpack1("N")
  track = StringIO.new(io.read(tlen))
  tempo = 500_000
  tick = 0
  notes = []
  ons = {}
  until track.eof?
    tick += read_vlq(track)
    status = track.readbyte
    if status == 0xFF
      typ = track.readbyte
      len = read_vlq(track)
      body = track.read(len)
      tempo = ("\x00" + body).unpack1("N") if typ == 0x51 && body.bytesize == 3
      break if typ == 0x2F
    elsif status & 0xF0 == 0x90
      pitch = track.readbyte
      vel = track.readbyte
      if vel.zero?
        on = ons.delete(pitch)
        notes << { pitch: pitch, start: on[:tick], dur: tick - on[:tick], vel: on[:vel] } if on
      else
        ons[pitch] = { tick: tick, vel: vel }
      end
    elsif status & 0xF0 == 0x80
      pitch = track.readbyte
      track.readbyte
      on = ons.delete(pitch)
      notes << { pitch: pitch, start: on[:tick], dur: tick - on[:tick], vel: on[:vel] } if on
    end
  end
  bpm = 60_000_000.0 / tempo
  { notes: notes, ppq: ppq, bpm: bpm }
end

def analog_render(notes, ppq, bpm, seconds: 45)
  samples = Array.new((RATE * seconds).ceil, 0.0)
  ladder = AnalogSynth::Ladder.new(rate: RATE)
  notes.each do |n|
    next if n[:pitch].between?(DRUM_LO, DRUM_HI)

    hz = 440.0 * (2.0**((n[:pitch] - 69) / 12.0))
    t0 = n[:start].to_f / ppq * 60.0 / bpm
    t1 = t0 + (n[:dur].to_f / ppq * 60.0 / bpm)
    next if t0 >= seconds

    t1 = [t1, seconds].min
    i0 = (t0 * RATE).floor
    i1 = (t1 * RATE).floor
    gain = n[:vel] / 127.0 * 0.15
    phase = 0.0
    (i0...i1).each do |i|
      break if i >= samples.length

      phase += hz / RATE
      phase -= 1.0 while phase >= 1.0
      env = 1.0 - ((i - i0).to_f / (i1 - i0 + 1))
      s = AnalogSynth.wave(:saw, phase)
      samples[i] += ladder.process(s * gain * env, [hz * 4, 2400].min, 0.35)
    end
  end
  peak = samples.map(&:abs).max
  peak = 1.0 if peak < 1e-6
  scale = 0.85 / peak
  samples.map { |s| (s * scale * 32_767).round.clamp(-32_767, 32_767) }
end

def write_wav(path, pcm)
  data = pcm.pack("s*")
  hdr = "RIFF#{[36 + data.bytesize].pack('V')}WAVEfmt "
  hdr << [16, 1, 1, RATE, RATE * 2, 2, 16].pack("VvvVVvv")
  hdr << "data#{[data.bytesize].pack('V')}"
  File.binwrite(path, hdr + data)
end

name = ARGV[0] || "home_improvement Project_home_improvement.mid"
mid = File.join(MID_DIR, name)
abort "missing #{mid}" unless File.file?(mid)
song = parse_mid(mid)
drums, pitched = song[:notes].partition { |n| n[:pitch].between?(DRUM_LO, DRUM_HI) }
warn "#{name}: #{pitched.size} pitched, #{drums.size} drum-range"

if drums.any?
  FileUtils.mkdir_p(CRATE)
  dest = File.join(CRATE, "hiphop_#{File.basename(name)}")
  FileUtils.cp(mid, dest)
  warn "drums copied to #{dest}"
end

tmp = "/tmp/liveset_play"
FileUtils.mkdir_p(tmp)
analog = File.join(tmp, "dilla.wav")
fluid = File.join(tmp, "fluid.wav")
mix = File.join(tmp, "mix.wav")
pcm = analog_render(pitched, song[:ppq], song[:bpm], seconds: 40)
write_wav(analog, pcm)
system("fluidsynth", "-ni", SF, mid, "-F", fluid, "-r", RATE.to_s, "-g", "0.6") or warn "fluidsynth failed"
if File.file?(fluid)
  system("ffmpeg", "-y", "-loglevel", "error", "-i", analog, "-i", fluid,
         "-filter_complex", "[0:a][1:a]amix=inputs=2:weights=1 0.7:duration=shortest,alimiter=limit=0.95",
         mix)
  exec("afplay", mix)
else
  exec("afplay", analog)
end
