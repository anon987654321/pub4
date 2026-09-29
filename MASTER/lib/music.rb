# frozen_string_literal: true

require "fileutils"

module Master
  module Music
    module Waveform
      module_function

      def write_wav(destination, samples, rate: 44_100)
        FileUtils.mkdir_p(File.dirname(destination))
        pcm = samples.map { |sample| (sample.clamp(-1.0, 1.0) * 32_767).round }.pack("s<*")
        data_size = pcm.bytesize
        byte_rate = rate * 2
        block_align = 2
        bits_per_sample = 16
        header = "RIFF" + [36 + data_size].pack("V") + "WAVE" +
                 "fmt " + [16].pack("V") + [1].pack("v") + [1].pack("v") +
                 [rate].pack("V") + [byte_rate].pack("V") +
                 [block_align].pack("v") + [bits_per_sample].pack("v") +
                 "data" + [data_size].pack("V")
        File.binwrite(destination, header + pcm)
        destination
      end
    end

    class AudioSink
      SAMPLE_RATE = 44_100
      CHANNELS = 1

      PLAYERS = {
        "sox" => %w[-q -t raw -r 44100 -e signed -b 16 -c 1 - -d],
        "ffplay" => %w[-f s16le -ar 44100 -ac 1 -nodisp -autoexit -loglevel quiet -i -],
      }.freeze

      class NoPlayerError < StandardError; end

      def initialize(player: self.class.default_player)
        @player = player or raise NoPlayerError, "no streaming player found (looked for #{PLAYERS.keys.join(', ')})"
      end

      def open
        name, args = @player
        @io = IO.popen([name, *args], "wb")
        yield self
      ensure
        close
      end

      def write(samples)
        pcm = samples.map { |sample| (sample.clamp(-1.0, 1.0) * 32_767).round }.pack("s<*")
        @io.write(pcm)
      end

      def close
        return unless @io
        @io.close_write unless @io.closed?
        @io.close unless @io.closed?
      rescue IOError
        nil
      ensure
        @io = nil
      end

      def self.default_player
        name, path = PLAYERS.keys.filter_map do |candidate|
          path = which(candidate)
          [candidate, path] if path
        end.first
        name && [path, PLAYERS.fetch(name)]
      end

      def self.which(cmd)
        candidates = [
          "/opt/homebrew/bin/#{cmd}",
          "/usr/local/bin/#{cmd}",
          *ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).map { |dir| File.join(dir, cmd) },
        ]
        candidates.uniq.find { |path| File.executable?(path) && !File.directory?(path) }
      end
    end

    class Synth
      RATE = 44_100
      SHAPES = %i[sine square triangle saw white brown].freeze
      NOISES = %i[white brown].freeze

      class << self
        def render(shape: :sine, hz: 440.0, seconds: 1.0, destination: nil, seed: 42)
          shape = shape.to_sym
          validate_shape!(shape)
          destination ||= default_destination(shape)
          frames = (seconds * RATE).round
          samples = build_samples(shape, hz, frames, seed)
          Waveform.write_wav(destination, samples, rate: RATE)
        end

        def play(path, loop: false)
          raise ArgumentError, "missing audio #{path}" unless File.file?(path)

          ffplay = player_path("ffplay")
          cmd = if loop && ffplay
                  [ffplay, "-loop", "0", "-nodisp", "-autoexit", "-loglevel", "quiet", "-i", path]
                elsif File.exist?("/usr/bin/afplay")
                  ["/usr/bin/afplay", path]
                elsif ffplay
                  [ffplay, "-nodisp", "-autoexit", "-i", path]
                else
                  raise "afplay or ffplay required"
                end

          log = File.open("/tmp/master-synth-play.log", "a")
          pid = Process.spawn(*cmd, out: log, err: log)
          log.close
          Process.detach(pid)
          pid
        end

        def oscillator(shape, hz, t)
          phase = (hz * t) % 1.0
          case shape
          when :square then phase < 0.5 ? 1.0 : -1.0
          when :triangle then phase < 0.5 ? 4.0 * phase - 1.0 : 3.0 - 4.0 * phase
          when :saw then 2.0 * phase - 1.0
          else Math.sin(2 * Math::PI * phase)
          end
        end

        def noise_samples(shape, frames, seed: 42) = noise(shape, frames, seed)

        private

        def validate_shape!(shape)
          return if SHAPES.include?(shape)
          raise ArgumentError, "unknown shape #{shape}; valid: #{SHAPES.join(', ')}"
        end

        def player_path(name)
          candidates = [
            "/opt/homebrew/bin/#{name}",
            "/usr/local/bin/#{name}",
            *ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).map { |dir| File.join(dir, name) },
          ]
          candidates.uniq.find { |path| File.executable?(path) && !File.directory?(path) }
        end

        def default_destination(shape)
          File.expand_path("~/master-#{shape}-#{Time.now.utc.strftime('%Y%m%dT%H%M%SZ')}.wav")
        end

        def build_samples(shape, hz, frames, seed)
          return noise(shape, frames, seed) if NOISES.include?(shape)
          Array.new(frames) { |i| oscillator(shape, hz, i.to_f / RATE) }
        end

        def noise(shape, frames, seed)
          rng = Random.new(seed)
          value = 0.0
          Array.new(frames) do
            raw = rng.rand * 2.0 - 1.0
            value = if shape == :white
                      raw
                    else
                      (value + 0.02 * raw).clamp(-1.0, 1.0)
                    end
            value * 0.8
          end
        end
      end
    end

    module Realtime
      RATE = AudioSink::SAMPLE_RATE
      BLOCK_FRAMES = 1_024

      module_function

      def play(shape: :sine, hz: 440.0, seconds: 3.0, sink: AudioSink.new)
        shape = shape.to_sym
        total_frames = (seconds * RATE).round
        noise = Synth.noise_samples(shape, total_frames) if Synth::NOISES.include?(shape)
        sink.open do |s|
          each_block(total_frames) do |first_frame, count|
            s.write(noise ? noise[first_frame, count] : Array.new(count) { |i| Synth.oscillator(shape, hz, (first_frame + i).to_f / RATE) })
          end
        end
      end

      def morph(hz: 440.0, seconds: 6.0, shapes: %i[sine square triangle], crossfade_seconds: 0.3, sink: AudioSink.new)
        segment_seconds = seconds / shapes.length
        fade = [crossfade_seconds, segment_seconds / 3.0].min
        total_frames = (seconds * RATE).round
        sink.open do |s|
          each_block(total_frames) do |first_frame, count|
            s.write(Array.new(count) { |i| morph_sample(shapes, hz, (first_frame + i).to_f / RATE, segment_seconds, fade) })
          end
        end
      end

      def morph_sample(shapes, hz, t, segment_seconds, fade)
        index = (t / segment_seconds).to_i.clamp(0, shapes.length - 1)
        into_segment = t - (index * segment_seconds)
        current = Synth.oscillator(shapes[index], hz, t)
        next_shape = shapes[index + 1]
        return current unless next_shape && into_segment >= segment_seconds - fade
        weight = (into_segment - (segment_seconds - fade)) / fade
        nxt = Synth.oscillator(next_shape, hz, t)
        ((1 - weight) * current) + (weight * nxt)
      end

      def each_block(total_frames)
        frame = 0
        while frame < total_frames
          count = [BLOCK_FRAMES, total_frames - frame].min
          yield frame, count
          frame += count
        end
      end
      private_class_method :each_block
    end

    class KickLoop
      RATE = 44_100
      BPM = 140.0
      BEATS = 4
      KICK_SECONDS = 0.32

      class << self
        def render(destination: nil)
          destination ||= default_destination
          bar_seconds = 60.0 / BPM * BEATS
          frames = (bar_seconds * RATE).round
          beat_frames = (bar_seconds / BEATS * RATE).round
          samples = Array.new(frames, 0.0)
          BEATS.times { |beat| render_kick!(samples, beat * beat_frames) }
          Waveform.write_wav(destination, samples, rate: RATE)
        end

        private

        def default_destination
          File.expand_path("~/master-techno-kick-#{Time.now.utc.strftime('%Y%m%dT%H%M%SZ')}.wav")
        end

        def render_kick!(samples, start)
          phase = 0.0
          attack_frames = (RATE * 0.0012).round
          kick_frames = (KICK_SECONDS * RATE).round

          kick_frames.times do |offset|
            frame = start + offset
            break if frame >= samples.length
            t = offset.to_f / RATE
            attack = [offset.to_f / attack_frames, 1.0].min
            hz = 42.0 + 58.0 * Math.exp(-t * 11.0)
            phase += 2 * Math::PI * hz / RATE
            body = Math.sin(phase) * Math.exp(-t * 9.0)
            click = Math.sin(2 * Math::PI * 1800 * t) * Math.exp(-t * 120)
            sample = body + (click * attack)
            samples[frame] += (Math.tanh(sample * 3.0) / Math.tanh(3.0)) * 0.95 * attack
          end
        end
      end
    end

    module Rhythm
      module_function

      def grid(bars: 1, beats_per_bar: 4, subdivisions_per_beat: 4, bpm: 140.0, swing: 0.0, dilla: false, seed: 42)
        beat_seconds = 60.0 / bpm
        step_seconds = beat_seconds / subdivisions_per_beat
        count = bars * beats_per_bar * subdivisions_per_beat
        rng = Random.new(seed)
        Array.new(count) do |step|
          at = step * step_seconds
          dilla_offset = dilla && step.odd? ? step_seconds * (0.12 + rng.rand * 0.10) : 0.0
          swing_offset = swing.positive? && step.odd? ? step_seconds * swing : 0.0
          at += dilla_offset + swing_offset
          { step:, at:, offset: dilla_offset + swing_offset }
        end
      end
    end

    module Theory
      NOTE_NAMES = %w[C C# D D# E F F# G G# A A# B].freeze
      SCALES = {
        major: [0, 2, 4, 5, 7, 9, 11],
        minor: [0, 2, 3, 5, 7, 8, 10],
        dorian: [0, 2, 3, 5, 7, 9, 10],
        phrygian: [0, 1, 3, 5, 7, 8, 10],
        lydian: [0, 2, 4, 6, 7, 9, 11],
        mixolydian: [0, 2, 4, 5, 7, 9, 10],
        locrian: [0, 1, 3, 5, 6, 8, 10],
        harmonic_minor: [0, 2, 3, 5, 7, 8, 11],
        melodic_minor: [0, 2, 3, 5, 7, 9, 11],
      }.freeze

      QUALITIES = {
        major: [0, 4, 7],
        minor: [0, 3, 7],
        dominant7: [0, 4, 7, 10],
        minor7: [0, 3, 7, 10],
        major7: [0, 4, 7, 11],
        half_diminished: [0, 3, 6, 10],
        diminished: [0, 3, 6],
      }.freeze

      PROGRESSIONS = {
        dilla_love: %w[i7 iv7 bVII7 bVI7],
        neo_soul_loop: %w[i7 iv7 bVII7 bVI7],
        techno_pulse: %w[i i bVI bVII],
        jazz_loop: %w[ii7 V7 I7 vi7],
        modal_drift: %w[i7 III7 bVII7 iv7],
      }.freeze

      module_function

      def note_index(note)
        note = note.to_s
        index = NOTE_NAMES.index(note)
        return index if index
        NOTE_NAMES.index(note[0].upcase + note[1].to_s)
      end

      def scale(root: "C", name: :major)
        base = note_index(root) || 0
        SCALES.fetch(name.to_sym).map { |offset| NOTE_NAMES[(base + offset) % 12] }
      end

      def chord(root: "C", quality: :minor7)
        base = note_index(root) || 0
        QUALITIES.fetch(quality.to_sym).map { |offset| NOTE_NAMES[(base + offset) % 12] }
      end

      def progression(root: "C", name: :dilla_love, scale: :minor)
        symbols = PROGRESSIONS.fetch(name.to_sym)
        base = note_index(root) || 0
        symbols.map { |symbol| chord_from_symbol(symbol, base) }
      end

      def chord_from_symbol(symbol, base)
        quality = if symbol.include?("7")
                    symbol.include?("m") || symbol.match?(/\Ai7/) ? :minor7 : :dominant7
                  elsif symbol.include?("m")
                    :minor
                  else
                    :major
                  end
        root = NOTE_NAMES[(base + degree(symbol)) % 12]
        chord(root:, quality:)
      end

      def degree(symbol)
        case symbol
        when "i7", "i", "I", "I7" then 0
        when "ii7", "ii", "II", "II7" then 2
        when "iii7", "iii", "III", "III7" then 4
        when "iv7", "iv", "IV", "IV7" then 5
        when "v7", "v", "V", "V7" then 7
        when "vi7", "vi", "VI", "VI7" then 9
        when "vii7", "vii", "VII", "VII7" then 10
        when "bVII", "bVII7" then 10
        when "bVI", "bVI7" then 8
        else 0
        end
      end
    end
  end
end
