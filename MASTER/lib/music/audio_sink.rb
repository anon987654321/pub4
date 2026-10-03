# frozen_string_literal: true

module Master
  module Music
    # A live pipe to the speaker: samples in, sound out, nothing written to
    # disk. Waveform.write_wav's packing convention (16-bit signed
    # little-endian, `pack("s<*")`) is the format every player below reads,
    # so a WAV and a live stream differ only in whether a header and a file
    # sit between them.
    #
    # This is deliberately not Voice::Playback's player. That module invokes
    # afplay/ffplay/mpv/aucat *on a finished file path* -- a one-shot,
    # blocking argument, not a stream a caller can keep writing to. sox and
    # ffplay both also accept raw PCM on stdin, which is a different
    # invocation of the same binaries, not the same call. Forcing one shared
    # code path across "play this file" and "keep this pipe fed" would be
    # the wrong kind of reuse; sharing the sample format and the "probe for
    # what's on PATH" convention is the right amount.
    class AudioSink
      SAMPLE_RATE = 44_100
      CHANNELS = 1

      # sox first: built for exactly this (raw PCM on stdin to the default
      # device). ffplay's raw-PCM stdin mode is the fallback, same as
      # Synth.play falls back to it for file playback.
      PLAYERS = {
        # -q: sox otherwise redraws a progress meter on the terminal MASTER is
        # talking on.
        "sox" => %w[-q -t raw -r 44100 -e signed -b 16 -c 1 - -d],
        "ffplay" => %w[-f s16le -ar 44100 -ac 1 -nodisp -autoexit -loglevel quiet -i -],
      }.freeze

      class NoPlayerError < StandardError; end

      def initialize(player: self.class.default_player)
        @player = player or raise NoPlayerError, "no streaming player found (looked for #{PLAYERS.keys.join(', ')})"
      end

      # Opens the pipe, yields self so a caller writes frames as they are
      # generated, closes on the way out (including on an exception, so a
      # Ctrl-C during generation does not leave the player process dangling).
      def open
        name, args = @player
        @io = IO.popen([name, *args], "wb")
        yield self
      ensure
        close
      end

      # samples: an array of floats in [-1.0, 1.0], same range Waveform
      # expects. Clamped the same way write_wav clamps, so a stray value out
      # of range cannot pack into noise instead of raising.
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
  end
end
