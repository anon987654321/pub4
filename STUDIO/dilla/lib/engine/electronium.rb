# frozen_string_literal: true
#
# The MIDI electronium.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.

# =============================================================================
# ELECTRONIUM — Raymond Scott × J Dilla (midilib MIDI + full-engine bridge)
# All logic lives here; no sidecar electronium.rb. Lazy-loads midilib at runtime.
# =============================================================================

module DillaElectronium
  PPQN = 480
  F_MINOR_SCALE = [65, 67, 68, 70, 72, 73, 75].freeze # F4–Eb5

  # Lush 9th voicings (merged engine pads + MIDI export).
  CHORDS = {
    fm9: [53, 56, 60, 63, 67], dbmaj9: [49, 53, 56, 60, 63], eb9: [51, 55, 58, 63, 65],
    bbm9: [46, 49, 53, 56, 60], cm7b5: [48, 51, 54, 58], c7alt: [48, 52, 58, 61, 63],
  }.freeze
  PROGRESSION = %i[fm9 dbmaj9 eb9 bbm9 cm7b5 fm9 c7alt fm9].freeze

  # Classic 7th cycle from the Electronium essay / "The Light" family.
  CHORDS_CLASSIC = {
    fm7: [65, 68, 72, 75], dbmaj7: [61, 65, 68, 72], eb7: [63, 67, 70, 75],
    bbm7: [58, 61, 65, 68], cm7b5: [60, 63, 66, 70], c7: [60, 64, 67, 70],
  }.freeze
  PROGRESSION_CLASSIC = %i[fm7 dbmaj7 eb7 bbm7 cm7b5 fm7 c7 fm7].freeze

  DRUMS = { kick: 36, snare: 38, closed_hat: 42, open_hat: 46 }.freeze

  module_function

  def classic?
    ENV["ELECTRONIUM_CLASSIC"] == "1"
  end

  def chord_bank
    classic? ? CHORDS_CLASSIC : CHORDS
  end

  def progression
    classic? ? PROGRESSION_CLASSIC : PROGRESSION
  end

  # Poly-temporal offsets — kick early, snare late, hats lopsided (Dilla Time).
  module Groove
    module_function

    def rng
      @rng ||= Random.new((ENV["SEED"] || ENV["GEN_SEED"] || Process.pid).to_i)
    end

    def offset_ticks(type)
      case type
      when :kick then rng.rand(-3..0)      # rush the downbeat slightly
      when :snare then rng.rand(0..5)      # lazy backbeat
      when :hat then rng.rand(-2..2)
      when :bass, :melody then rng.rand(-4..4)
      else 0
      end
    end

    def beat_to_ticks(beat, type = :melody)
      ((beat * DillaElectronium::PPQN) + offset_ticks(type)).round.clamp(0, 1 << 30)
    end
  end

  class TrackBuilder
    def initialize(sequence, name, channel)
      @sequence = sequence
      @track = MIDI::Track.new(sequence)
      @track.name = name
      @sequence.tracks << @track
      @channel = channel
    end

    def note(note, start_beat, duration_beats, velocity, feel: :melody)
      return if duration_beats <= 0
      start = Groove.beat_to_ticks(start_beat, feel)
      stop = [start + (duration_beats * PPQN).round, start + 1].max
      on = MIDI::NoteOn.new(@channel, note, velocity.clamp(1, 127))
      on.time_from_start = start
      off = MIDI::NoteOff.new(@channel, note, 0)
      off.time_from_start = stop
      @track.events << on
      @track.events << off
    end

    def finish
      @track.events.sort_by! { |e| [e.time_from_start, e.is_a?(MIDI::NoteOff) ? 0 : 1] }
      @track.recalc_times
    end
  end

  class Composer
    def initialize(bpm:, bars:, classic: false, septuplet_hats: false)
      @bpm = bpm
      @bars = bars
      @classic = classic
      @septuplet_hats = septuplet_hats
      @sequence = MIDI::Sequence.new
      @sequence.ppqn = PPQN
      add_tempo_track
    end

    def write(path)
      add_drums
      add_bass
      add_chords
      add_melody
      File.open(path, "wb") { |f| @sequence.write(f) }
      path
    end

    private

    def chord_bank
      @classic ? CHORDS_CLASSIC : CHORDS
    end

    def progression
      @classic ? PROGRESSION_CLASSIC : PROGRESSION
    end

    def add_tempo_track
      track = MIDI::Track.new(@sequence)
      @sequence.tracks << track
      track.events << MIDI::Tempo.new(MIDI::Tempo.bpm_to_mpq(@bpm))
      title = @classic ? "Dilla Electronium (classic 7ths)" : "Dilla Electronium"
      track.events << MIDI::MetaEvent.new(MIDI::META_SEQ_NAME, title)
      track.events << MIDI::MetaEvent.new(MIDI::META_TIME_SIG, [4, 2, 24, 8].pack("cccc"))
    end

    def add_drums
      drums = TrackBuilder.new(@sequence, "drums", 9)
      if @classic
        add_drums_classic(drums)
      else
        add_drums_dilla(drums)
      end
      drums.finish
    end

    def add_drums_dilla(drums)
      @bars.times do |bar|
        base = bar * 4.0
        [0.0, 1.75, 2.5, 3.5].each { |beat| drums.note(DRUMS[:kick], base + beat, 0.18, 105, feel: :kick) }
        [1.0, 3.0].each { |beat| drums.note(DRUMS[:snare], base + beat, 0.12, 92, feel: :snare) }
        drums.note(DRUMS[:snare], base + 2.75, 0.08, 42, feel: :snare) if bar.odd?
        if @septuplet_hats
          (0...4).each do |beat|
            [0.0, 3.0 / 7.0].each do |sub|
              drums.note(DRUMS[:closed_hat], base + beat + sub, 0.08, Groove.rng.rand(50..70), feel: :hat)
            end
          end
        else
          8.times do |step|
            drums.note(DRUMS[:closed_hat], base + step * 0.5 + (step.odd? ? 0.055 : 0.0), 0.08,
                        step.odd? ? 48 : 68, feel: :hat)
          end
        end
        drums.note(DRUMS[:open_hat], base + 3.5, 0.18, 58, feel: :hat) if (bar % 4).zero?
      end
    end

    def add_drums_classic(drums)
      groups = (@bars / 2.0).ceil
      groups.times do |g|
        base = g * 8.0
        [0.0, 2.0, 4.0, 6.0].each { |beat| drums.note(DRUMS[:kick], base + beat, 0.12, 100, feel: :kick) }
        [1.0, 3.0, 5.0, 7.0].each { |beat| drums.note(DRUMS[:snare], base + beat, 0.12, 90, feel: :snare) }
        (0...8).each do |beat|
          [0.0, 3.0 / 7.0].each do |sub|
            drums.note(DRUMS[:closed_hat], base + beat + sub, 0.08, Groove.rng.rand(50..70), feel: :hat)
          end
        end
      end
    end

    def add_bass
      bass = TrackBuilder.new(@sequence, "bass", 0)
      chord_cycle.each_with_index do |chord_name, index|
        root = chord_bank.fetch(chord_name).first - (@classic ? 24 : 12)
        start = index * 2.0
        [0.0, 0.75, 1.5].each_with_index do |off, i|
          vel = [98, 72, 86][i]
          dur = [0.62, 0.25, 0.38][i]
          note = i == 1 ? root + 12 : root
          bass.note(note, start + off, dur, vel, feel: :bass)
        end
      end
      bass.finish
    end

    def add_chords
      pads = TrackBuilder.new(@sequence, "electric-piano", 1)
      chord_cycle.each_with_index do |chord_name, index|
        transpose = @classic ? 0 : 12
        chord_bank.fetch(chord_name).each_with_index do |note, voice|
          pads.note(note + transpose, index * 2.0, 1.82, Groove.rng.rand(42..58) + voice * 4, feel: :melody)
        end
      end
      pads.finish
    end

    def add_melody
      lead = TrackBuilder.new(@sequence, "lead-chops", 2)
      note_index = 2
      direction = 1
      steps = @bars * (@classic ? 8 : 4)
      steps.times do |step|
        if Groove.rng.rand < 0.78
          note = F_MINOR_SCALE[note_index] + (Groove.rng.rand < 0.25 ? 12 : 0)
          dur = [0.25, 0.5, 0.75, 1.0].sample(random: Groove.rng)
          lead.note(note, step * (@classic ? 0.5 : 1.0), dur, Groove.rng.rand(62..88), feel: :melody) if dur.positive?
        end
        note_index += direction * (Groove.rng.rand < 0.2 ? 2 : 1)
        if note_index >= F_MINOR_SCALE.length - 1
          note_index = F_MINOR_SCALE.length - 2
          direction = -1
        elsif note_index <= 0
          note_index = 1
          direction = 1
        end
        direction *= -1 if Groove.rng.rand < 0.18
      end
      lead.finish
    end

    def chord_cycle
      repeats = ((@bars * 4.0) / (progression.length * 2.0)).ceil
      progression.cycle.take(progression.length * repeats)
    end
  end
end

def electronium_ensure_loaded!
  DillaMusicGems.midi_ensure!
rescue LoadError
  abort "midilib required — cd MASTER && bundle install"
end

def electronium_render_audio(midi_path, audio_path = nil)
  require_playback_tool!
  audio_path ||= midi_path.sub(/\.mid\z/i, ".wav")
  sf2 = pad_soundfont_path
  abort "no soundfont — install GeneralUser-GS or set DILLA_SOUNDFONT" unless sf2 && File.exist?(sf2)
  wav_tmp = audio_path.end_with?(".mp3") ? audio_path.sub(/\.mp3\z/i, ".wav") : audio_path
  fluidsynth_render!(wav_tmp, sf2, midi_path, gain: 1.4)
  if audio_path.end_with?(".mp3")
    sh! "ffmpeg", "-y", "-i", wav_tmp, "-acodec", "libmp3lame", "-ab", "192k", audio_path
    FileUtils.rm_f(wav_tmp)
  end
  puts "rendered #{audio_path}"
  audio_path
end

def electronium_full_render(destination = File.join(OUTPUT_DIR, "electronium.wav"), classic: false)
  track = classic ? "electronium_classic" : "electronium_loop"
  ENV["TRACK"] = track
  apply_track_soul_profile!(track, force: false)
  apply_best_defaults!
  n = (ENV["BARS"] || 32).to_i
  render_dilla(destination, n)
  puts "electronium full render → #{destination} (TRACK=#{track} #{n} bars)"
  destination
end

def electronium_generate(destination = File.join(OUTPUT_DIR, "electronium.mid"), classic: false,
                         render_audio: false, full_render: false)
  if full_render
    out = destination.sub(/\.mid\z/i, ".wav")
    return electronium_full_render(out, classic:)
  end
  electronium_ensure_loaded!
  FileUtils.rm_f(destination)
  n_bars = [(ENV["BARS"] || 32).to_i, 8].max
  sept = ENV.fetch("ELECTRONIUM_SEPTUPLET", classic ? "1" : "0") != "0"
  path = DillaElectronium::Composer.new(
    bpm: bpm.to_i, bars: n_bars, classic:, septuplet_hats: sept,
  ).write(destination)
  puts "wrote #{path} (#{classic ? 'classic 7ths' : 'lush 9ths'}, #{n_bars} bars @ #{bpm.to_i} BPM)"
  if render_audio
    audio = destination.sub(/\.mid\z/i, ".mp3")
    electronium_render_audio(path, audio)
    play(audio) if tool_available?("ffplay")
  end
  path
end

def electronium_dispatch!
  classic = ENV["ELECTRONIUM_CLASSIC"] == "1"
  render_audio = ENV["ELECTRONIUM_RENDER"] == "1"
  dest = ARGV.find { |a| a =~ /\.(mid|mp3|wav)\z/i } || File.join(OUTPUT_DIR, "electronium.mid")
  electronium_generate(dest, classic:, render_audio:)
end
