# ------------------------------------------------------------------- MIDI
# A Standard MIDI File, format 0: the chords on channel 1 and the drums on channel 10
# (kick 36, snare 38, hat 42). Times are the same ones the WAV uses.
module MIDI
  PPQN = 480
  DRUM_NOTES = { 'kick' => 36, 'snare' => 38, 'hat' => 42 }.freeze

  def self.vlq(number)
    bytes = [number & 0x7f]
    while (number >>= 7).positive?
      bytes.unshift((number & 0x7f) | 0x80)
    end
    bytes.pack('C*')
  end

  # A Standard MIDI File of notes on one channel, for a soundfont to play: each note is
  # [start seconds, length seconds, midi note, velocity]. The file runs at 120 beats a minute,
  # so a second is 960 ticks, and ends `tail` seconds after the last note so the soundfont's
  # releases are rendered before it stops.
  def self.write_notes(path, notes, program:, bank: 0, tail: 2.5)
    ticks = ->(seconds) { (seconds * 2 * PPQN).round }
    events = notes.flat_map do |start, length, midi, velocity|
      [[ticks.call(start), 0x90, midi, velocity.clamp(1, 127)], [ticks.call(start + length), 0x80, midi, 0]]
    end
    ending = events.map(&:first).max.to_i + ticks.call(tail)
    track = "\x00\xFF\x51\x03".b + [500_000].pack('N')[1, 3]
    track << "\x00\xB0\x00".b << [bank].pack('C') << "\x00\xC0".b << [program].pack('C')
    last = 0
    events.sort_by { |tick, status, *| [tick, status & 0xf0 == 0x80 ? 0 : 1] }.each do |tick, status, note, vel|
      track << vlq(tick - last) << [status, note, vel].pack('C3')
      last = tick
    end
    track << vlq(ending - last) << "\xFF\x2F\x00".b
    File.binwrite(path, 'MThd'.b + [6, 0, 1, PPQN].pack('Nnnn') + 'MTrk'.b + [track.bytesize].pack('N') + track)
  end

  def self.write(path, names, bpm, beats, hits, search: true)
    ticks = ->(seconds) { (seconds * bpm / 60.0 * PPQN).round }
    chord_len = (beats * PPQN).round
    events = []
    Chords.midi_notes(names, search:).each_with_index do |notes, idx|
      notes.each do |n|
        events << [idx * chord_len, 0x90, n, 80]
        events << [(idx + 1) * chord_len, 0x80, n, 0]
      end
    end
    hits.each do |role, time|
      on = ticks.call(time)
      events << [on, 0x99, DRUM_NOTES.fetch(role), 100]
      events << [on + 30, 0x89, DRUM_NOTES.fetch(role), 0]
    end
    track = "\x00\xFF\x51\x03".b + [(60_000_000 / bpm).round].pack('N')[1, 3]
    last = 0
    events.sort_by { |tick, status, *| [tick, status & 0xf0 == 0x80 ? 0 : 1] }.each do |tick, status, note, vel|
      track << vlq(tick - last) << [status, note, vel].pack('C3')
      last = tick
    end
    track << "\x00\xFF\x2F\x00".b
    header = 'MThd'.b + [6, 0, 1, PPQN].pack('Nnnn')
    File.binwrite(path, header + 'MTrk'.b + [track.bytesize].pack('N') + track)
  end
end

