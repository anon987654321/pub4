#!/usr/bin/env ruby
# frozen_string_literal: true

# Sweep Ableton .als (gzip XML) and write Type-0 MIDI of every KeyTrack.
# KeyTrack Id is the MIDI pitch. Time/Duration are in beats.
require "fileutils"
require "zlib"

ROOT = "/Users/mac/Downloads/livesets"
OUT = File.expand_path("livesets_midi", __dir__)
PPQ = 480

def vlq(n)
  bytes = [n & 0x7f]
  n >>= 7
  while n.positive?
    bytes.unshift((n & 0x7f) | 0x80)
    n >>= 7
  end
  bytes.pack("C*").b
end

def midi_file(notes, tempo_bpm)
  usec = (60_000_000 / [tempo_bpm, 1].max).to_i
  events = []
  notes.each do |n|
    on = (n[:beat] * PPQ).round
    off = ((n[:beat] + n[:dur]) * PPQ).round
    off = on + 1 if off <= on
    events << [on, 0x90, n[:pitch], n[:vel]]
    events << [off, 0x80, n[:pitch], 0]
  end
  events.sort_by! { |e| [e[0], e[1]] }
  track = String.new(encoding: Encoding::BINARY)
  track << "\x00\xFF\x51\x03".b << [usec].pack("N")[1, 3]
  last = 0
  events.each do |tick, status, pitch, vel|
    delta = [tick - last, 0].max
    track << vlq(delta) << [status, pitch, vel].pack("C*")
    last = tick
  end
  track << vlq(0) << "\xFF\x2F\x00".b
  header = "MThd".b + [6].pack("N") + [0, 1, PPQ].pack("n*")
  header + "MTrk".b + [track.bytesize].pack("N") + track
end

def extract(als)
  xml = Zlib::GzipReader.open(als, &:read)
  tempo = xml[%r{<Tempo>.*?<Manual Value="([0-9.]+)" }m, 1].to_f
  tempo = 120.0 if tempo < 20 || tempo > 300
  notes = []
  xml.scan(%r{<KeyTrack Id="(\d+)">(.*?)</KeyTrack>}m) do |pitch, body|
    p = pitch.to_i
    next if p.negative? || p > 127

    body.scan(/<MidiNoteEvent Time="([^"]+)" Duration="([^"]+)" Velocity="([^"]+)"/) do |t, d, v|
      notes << { pitch: p, beat: t.to_f, dur: [d.to_f, 0.05].max, vel: [[v.to_i, 1].max, 127].min }
    end
  end
  [tempo, notes]
end

FileUtils.mkdir_p(OUT)
written = 0
skipped = 0
Dir.glob(File.join(ROOT, "**", "*.als")).each do |als|
  next if als.include?("/Backup/")

  tempo, notes = extract(als)
  if notes.empty?
    skipped += 1
    next
  end
  rel = als.delete_prefix(ROOT + "/").sub(/\.als\z/, ".mid")
  dest = File.join(OUT, rel.tr("/", "_"))
  File.binwrite(dest, midi_file(notes, tempo))
  written += 1
  warn format("%4d notes  tempo=%5.1f  %s", notes.size, tempo, File.basename(dest))
end
warn "wrote #{written} midi files to #{OUT} (#{skipped} als had no notes)"
