# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"

module Master
  module Voice
    # The startup chime: a second of lofi 8-bit FM, written as notes in voice.yml under boot_sound and
    # synthesised here (pulse, triangle and two-operator FM voices, a bit crush), cached as a wav
    # outside the repo and played once when a session starts. MASTER_BOOT_SOUND=0 or `enabled: false` is
    # silence; it never plays without a terminal.
    module BootSound
      RATE = 22_050
      TAU = Math::PI * 2

      module_function

      def config = Master.load_yaml(Master.data_path("voice.yml"), default: {}).fetch("boot_sound", {})

      def enabled?(settings = config)
        return false if ENV["MASTER_BOOT_SOUND"] == "0" || ENV["MASTER_SKIP_TTS"] == "1" || ENV["CI"]

        settings["enabled"] == true && $stdout.tty?
      end

      # Plays the chime in the background. True when a player was started.
      def play(settings = config)
        return false unless enabled?(settings)

        player = settings.fetch("player").to_s.split
        return false unless Master::Voice::Playback.which(player.first)

        path = ensure_wav(settings)
        argv = [*player.map { |word| format(word, volume: settings.fetch("volume", 0.5)) }, path]
        pid = Process.spawn(*argv, **Master::Io::ProcessSpawn.options(out: File::NULL, err: File::NULL, pgroup: true))
        Process.detach(pid)
        true
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Voice::BootSound.play")
        false
      end

      def ensure_wav(settings = config)
        path = File.join(Dir.home, ".master", "boot_sound", "chime_#{cache_key(settings)}.wav")
        return path if File.size?(path)

        FileUtils.mkdir_p(File.dirname(path))
        File.binwrite(path, wav(render(settings)))
        path
      end

      def cache_key(settings)
        Digest::SHA256.hexdigest(JSON.generate(settings.fetch("notes")) + settings.fetch("crush_bits", 0).to_s)[0, 12]
      end

      # Notes are { "midi", "ms", "wave" (pulse|triangle|fm), "duty", "ratio", "index", "gain" }, played in turn;
      # a note with "with": true sounds with the one before it, as a chord.
      def render(settings)
        bits = settings.fetch("crush_bits", 0).to_i
        out = score(settings.fetch("notes"))
        out = out.map { |sample| crush(sample, bits) } if bits.positive?

        out.map { |sample| sample.clamp(-1.0, 1.0) }
      end

      def score(notes)
        out = []
        cursor = previous_start = 0

        notes.each do |note|
          start = note["with"] ? previous_start : cursor
          samples = voice(note)
          mix(out, samples, start:)
          previous_start = start
          cursor = start + samples.size unless note["with"]
        end
        out
      end

      def voice(note)
        count = (note.fetch("ms") * RATE / 1000.0).to_i
        freq = 440.0 * (2.0**((note.fetch("midi") - 69) / 12.0))
        gain = note.fetch("gain", 0.4)

        Array.new(count) do |index|
          envelope(index, count) * gain * wave(note, freq:, seconds: index.to_f / RATE)
        end
      end

      def wave(note, freq:, seconds:)
        phase = (freq * seconds) % 1.0

        case note.fetch("wave", "pulse")
        when "triangle" then phase < 0.5 ? (4.0 * phase) - 1.0 : 3.0 - (4.0 * phase)
        when "fm" then fm(note, freq:, seconds:)
        else phase < note.fetch("duty", 0.5) ? 1.0 : -1.0
        end
      end

      def fm(note, freq:, seconds:)
        modulator = Math.sin(TAU * freq * note.fetch("ratio", 2.0) * seconds)
        Math.sin((TAU * freq * seconds) + (note.fetch("index", 2.0) * modulator))
      end

      # A 4 ms attack and an exponential fall, so each note is a blip, not a drone.
      def envelope(index, count)
        attack = [(0.004 * RATE).to_i, 1].max
        rise = [index.to_f / attack, 1.0].min

        rise * Math.exp(-3.0 * index / count)
      end

      def mix(out, samples, start:)
        out.fill(0.0, out.size...(start + samples.size)) if out.size < start + samples.size
        samples.each_with_index { |sample, i| out[start + i] += sample }
      end

      def crush(sample, bits)
        levels = (2**(bits - 1)).to_f
        (sample * levels).round / levels
      end

      def wav(samples)
        pcm = samples.map { |sample| (sample * 32_767).round }.pack("s<*")
        header = ["RIFF", 36 + pcm.bytesize, "WAVE", "fmt ", 16, 1, 1, RATE, RATE * 2, 2, 16, "data", pcm.bytesize]
        header.pack("a4Va4a4VvvVVvva4V") + pcm
      end
    end
  end
end
