#!/usr/bin/env ruby
# frozen_string_literal: true

# Dilla Electronium: Raymond Scott-style generative MIDI with Dilla microtiming.
# Inspired by the public gist noted in README.md, adapted for pub4 as a safe
# generator: no auto-install, no network, no shell renderer.

begin
  require "midilib"
  require "midilib/sequence"
  require "midilib/track"
  require "midilib/consts"
rescue LoadError
  warn "midilib is required. Install it outside this script: gem install midilib"
  exit 69
end

module DillaElectronium
  PPQN = 480
  BPM = Integer(ENV.fetch("BPM", "86"))
  BARS = Integer(ENV.fetch("BARS", "32"))

  F_MINOR = [65, 67, 68, 70, 72, 73, 75].freeze
  CHORDS = {
    fm9: [53, 56, 60, 63, 67],
    dbmaj9: [49, 53, 56, 60, 63],
    eb9: [51, 55, 58, 63, 65],
    bbm9: [46, 49, 53, 56, 60],
    cm7b5: [48, 51, 54, 58],
    c7alt: [48, 52, 58, 61, 63]
  }.freeze
  PROGRESSION = %i[fm9 dbmaj9 eb9 bbm9 cm7b5 fm9 c7alt fm9].freeze

  DRUMS = {
    kick: 36,
    snare: 38,
    closed_hat: 42,
    open_hat: 46
  }.freeze

  module Groove
    module_function

    def offset_ticks(type)
      case type
      when :kick then rand(-5..1)
      when :snare then rand(2..9)
      when :hat then rand(-3..4)
      when :bass then rand(-4..5)
      else rand(-5..5)
      end
    end

    def beat_to_ticks(beat, type = :melody)
      ((beat * PPQN) + offset_ticks(type)).round.clamp(0, 1 << 30)
    end
  end

  class TrackBuilder
    include MIDI

    def initialize(sequence, name, channel)
      @sequence = sequence
      @track = Track.new(sequence)
      @track.name = name
      @sequence.tracks << @track
      @channel = channel
    end

    def note(note, start_beat, duration_beats, velocity, feel: :melody)
      return if duration_beats <= 0

      start = Groove.beat_to_ticks(start_beat, feel)
      stop = [start + (duration_beats * PPQN).round, start + 1].max
      @track.events << NoteOn.new(@channel, note, velocity.clamp(1, 127), 0, start)
      @track.events << NoteOff.new(@channel, note, 0, 0, stop)
    end

    def finish
      @track.events.sort_by! { |event| [event.time_from_start, event.is_a?(NoteOff) ? 0 : 1] }
      @track.recalc_times
    end
  end

  class Composer
    include MIDI

    def initialize(bpm: BPM, bars: BARS)
      @bpm = bpm
      @bars = bars
      @sequence = Sequence.new
      @sequence.ppqn = PPQN
      add_tempo_track
    end

    def write(path)
      add_drums
      add_bass
      add_chords
      add_melody
      File.open(path, "wb") { |file| @sequence.write(file) }
      path
    end

    private

    def add_tempo_track
      track = Track.new(@sequence)
      @sequence.tracks << track
      track.events << Tempo.new(Tempo.bpm_to_mpq(@bpm))
      track.events << MetaEvent.new(META_SEQ_NAME, "Dilla Electronium")
      track.events << MetaEvent.new(META_TIME_SIG, [4, 2, 24, 8].pack("cccc"))
    end

    def add_drums
      drums = TrackBuilder.new(@sequence, "drums", 9)
      @bars.times do |bar|
        base = bar * 4.0
        [0.0, 1.75, 2.5, 3.5].each { |beat| drums.note(DRUMS[:kick], base + beat, 0.18, 105, feel: :kick) }
        [1.0, 3.0].each { |beat| drums.note(DRUMS[:snare], base + beat, 0.12, 92, feel: :snare) }
        [2.75].each { |beat| drums.note(DRUMS[:snare], base + beat, 0.08, 42, feel: :snare) } if bar.odd?
        8.times do |step|
          beat = base + (step * 0.5) + (step.odd? ? 0.055 : 0.0)
          drums.note(DRUMS[:closed_hat], beat, 0.08, step.odd? ? 48 : 68, feel: :hat)
        end
        drums.note(DRUMS[:open_hat], base + 3.5, 0.18, 58, feel: :hat) if (bar % 4).zero?
      end
      drums.finish
    end

    def add_bass
      bass = TrackBuilder.new(@sequence, "bass", 0)
      chord_cycle.each_with_index do |chord_name, index|
        root = CHORDS.fetch(chord_name).first - 12
        start = index * 2.0
        bass.note(root, start, 0.62, 98, feel: :bass)
        bass.note(root + 12, start + 0.75, 0.25, 72, feel: :bass)
        bass.note(root, start + 1.5, 0.38, 86, feel: :bass)
      end
      bass.finish
    end

    def add_chords
      chords = TrackBuilder.new(@sequence, "electric-piano", 1)
      chord_cycle.each_with_index do |chord_name, index|
        CHORDS.fetch(chord_name).each_with_index do |note, voice|
          chords.note(note + 12, index * 2.0, 1.82, 48 + (voice * 4), feel: :melody)
        end
      end
      chords.finish
    end

    def add_melody
      lead = TrackBuilder.new(@sequence, "lead-chops", 2)
      note_index = 2
      direction = 1
      (@bars * 4).times do |step|
        if rand < 0.78
          note = F_MINOR[note_index] + (rand < 0.25 ? 12 : 0)
          duration = [0.25, 0.5, 0.75].sample
          lead.note(note, step * 1.0, duration, rand(62..88), feel: :melody)
        end
        note_index += direction * (rand < 0.2 ? 2 : 1)
        if note_index >= F_MINOR.length - 1
          note_index = F_MINOR.length - 2
          direction = -1
        elsif note_index <= 0
          note_index = 1
          direction = 1
        end
        direction *= -1 if rand < 0.18
      end
      lead.finish
    end

    def chord_cycle
      repeats = ((@bars * 4.0) / (PROGRESSION.length * 2.0)).ceil
      PROGRESSION.cycle.take(PROGRESSION.length * repeats)
    end
  end
end

if $PROGRAM_NAME == __FILE__
  output = ARGV[0] || File.join(__dir__, "dilla_electronium.mid")
  path = DillaElectronium::Composer.new.write(output)
  puts "wrote #{path}"
end
