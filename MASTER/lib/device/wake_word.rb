# frozen_string_literal: true

require "json"
require "fileutils"
require "open3"
require "tempfile"

module Master
  module Device
    # Opt-in Android wake listener. It uses Termux:API for short microphone
    # windows and whisper.cpp for local phrase detection. No audio leaves the
    # device. A listener window is bounded so a hung recorder cannot own the
    # microphone forever.
    class WakeWord
      DEFAULT_PHRASES = ["hey master"].freeze
      WINDOW_SECONDS = 4
      RATE_HZ = 16_000
      STATE_PATH = ".master/wake_word.json"

      def initialize(root:, transcriber: nil, which: ->(cmd) { command?(cmd) }, run: Open3.method(:capture3),
                     sleeper: ->(seconds) { sleep seconds }, clock: -> { Time.now.to_i }, out: $stderr)
        @root = root
        @transcriber = transcriber
        @which = which
        @run = run
        @sleeper = sleeper
        @clock = clock
        @out = out
        @stop = false
      end

      def enabled?
        state["enabled"] == true && Device.android? && Device.termux?
      end

      def enable!(phrases: DEFAULT_PHRASES)
        normalized = normalize_phrases(phrases)
        raise ArgumentError, "wake word requires at least one phrase" if normalized.empty?

        write_state("enabled" => true, "phrases" => normalized, "enabled_at" => Time.now.utc.iso8601)
      end

      def disable!
        write_state("enabled" => false, "disabled_at" => Time.now.utc.iso8601)
      end

      def stop!
        @stop = true
        quit_recording
      end

      def phrases
        normalize_phrases(state.fetch("phrases", DEFAULT_PHRASES))
      end

      def run_forever
        return :disabled unless enabled?
        raise "wake word requires termux-microphone-record" unless @which.call("termux-microphone-record")
        raise "wake word requires whisper-cli" unless @which.call("whisper-cli")

        emit("wake0: listening for #{phrases.join(", ")}")
        until @stop
          heard = listen_once
          next if heard.to_s.empty?

          phrase = match(heard)
          emit("wake0: heard #{phrase}") if phrase
          yield(phrase, heard) if phrase && block_given?
        end
        :stopped
      ensure
        quit_recording
      end

      private

      def listen_once
        Tempfile.create(["master-wake-", ".wav"], binmode: true) do |file|
          file.close
          start_recording(file.path)
          @sleeper.call(WINDOW_SECONDS + 0.25)
          quit_recording
          return "" unless File.size?(file.path)

          transcribe(file.path)
        ensure
          File.unlink(file.path) rescue nil
        end
      rescue StandardError => e
        emit("wake0: #{e.class}: #{e.message}")
        @sleeper.call(1)
        ""
      end

      def start_recording(path)
        _out, err, status = @run.call(
          "termux-microphone-record", "-f", path, "-l", WINDOW_SECONDS.to_s,
          "-e", "wav", "-r", RATE_HZ.to_s, "-c", "1",
        )
        raise "microphone start failed: #{err}" unless status.success?
      end

      def quit_recording
        return unless @which.call("termux-microphone-record")

        @run.call("termux-microphone-record", "-q")
      rescue StandardError
        nil
      end

      def transcribe(path)
        model = whisper_model
        return "" unless model

        out, _err, status = @run.call(
          "whisper-cli", "-m", model, "-f", path, "-nt", "-np", "-l", "auto",
        )
        status.success? ? out.to_s.gsub(/\[[^\]]*\]|\([^)]*\)/, " ").split.join(" ") : ""
      rescue StandardError
        ""
      end

      def whisper_model
        named = ENV["MASTER_WHISPER_MODEL"].to_s
        return named if File.file?(named)

        %w[ggml-base.bin ggml-small.bin].map { |name| File.expand_path("~/.local/share/whisper/#{name}") }
          .find { |path| File.file?(path) && File.size(path).to_i >= 70_000_000 }
      end

      def match(text)
        normalized = text.to_s.downcase.gsub(/[^a-z0-9æøåäöüéèêëáàâ]/i, " ").split.join(" ")
        phrases.each do |phrase|
          return phrase if normalized == phrase || normalized.include?(phrase)
        end
        nil
      end

      def normalize_phrases(values)
        Array(values).map { |value| value.to_s.downcase.strip }.reject(&:empty?).uniq
      end

      def state
        path = File.join(@root, STATE_PATH)
        JSON.parse(File.read(path, encoding: "UTF-8"))
      rescue Errno::ENOENT, JSON::ParserError
        {}
      end

      def write_state(changes)
        path = File.join(@root, STATE_PATH)
        FileUtils.mkdir_p(File.dirname(path))
        current = state.merge(changes)
        File.write(path, JSON.pretty_generate(current) + "\n", mode: "w", encoding: "UTF-8")
      end

      def emit(line)
        @out.puts(line)
      end

      def command?(command)
        system("command", "-v", command, out: File::NULL, err: File::NULL)
      end
    end
  end
end
