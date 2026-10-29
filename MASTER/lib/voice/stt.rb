# frozen_string_literal: true

require "monitor"
require_relative "stt/null_backend"
require_relative "stt/vosk_backend"
require_relative "stt/whisper_cpp_backend"

module Master
  module Voice
    # Speech-to-text for the eyes-free loop.
    #
    # Sits after Vad: speech_start opens an utterance, frames are fed while the
    # user talks, speech_end finalizes text for Session/thinking.
    # Does not own the mic, VAD, or TTS.
    #
    # Backends soft-load. Missing native deps fall through to Null so voice
    # still boots. Prefer Vosk for streaming + grammar (approvals); whisper.cpp
    # for post-utterance quality on capable hosts.
    class Stt
      SAMPLE_RATE = 16_000

      DEFAULTS = {
        backend: :auto, # :auto | :vosk | :whisper_cpp | :null
        sample_rate: SAMPLE_RATE,
        language: "en",
        # Vosk
        vosk_model_path: nil, # ENV MASTER_VOSK_MODEL or default small en
        grammar: nil, # optional JSON array of phrases for APPROVAL
        # whisper.cpp
        whisper_binary: "whisper-cli",
        whisper_model_path: nil,
        whisper_timeout_s: 60,
      }.freeze

      Result = Data.define(:text, :partial?, :confidence, :backend, :ms, :raw)

      attr_reader :backend_name, :config

      def self.build(config: {})
        cfg = DEFAULTS.merge(config.transform_keys(&:to_sym))
        backend = resolve_backend(cfg)
        new(backend:, config: cfg)
      end

      def self.resolve_backend(cfg)
        choice = cfg[:backend].to_sym
        case choice
        when :null
          NullBackend.new
        when :vosk
          vosk = VoskBackend.try_load(cfg)
          raise LoadError, "Vosk STT requested but unavailable" unless vosk

          vosk
        when :whisper_cpp
          w = WhisperCppBackend.try_load(cfg)
          raise LoadError, "whisper.cpp STT requested but unavailable" unless w

          w
        else # :auto
          VoskBackend.try_load(cfg) ||
            WhisperCppBackend.try_load(cfg) ||
            NullBackend.new
        end
      end
      private_class_method :resolve_backend

      def initialize(backend: nil, config: {})
        @lock = Monitor.new
        @config = DEFAULTS.merge(config.transform_keys(&:to_sym))
        @backend = backend || NullBackend.new
        @backend_name = @backend.name
        @open = false
        @buffer = []
        @started_at_ms = nil
        @last_partial = ""
      end

      def available?
        @backend_name != :null
      end

      def start_utterance(at_ms: nil)
        @lock.synchronize do
          @open = true
          @buffer.clear
          @last_partial = ""
          @started_at_ms = at_ms || now_ms
          @backend.start_utterance if @backend.respond_to?(:start_utterance)
        end
        self
      end

      # Feed mono PCM: Float [-1,1] or Integer PCM16 samples.
      # Returns a partial Result when the backend streams; otherwise nil.
      def feed(samples)
        @lock.synchronize do
          return unless @open

          floats = normalize(samples)
          @buffer.concat(floats)
          partial = @backend.feed(floats)
          return if partial.nil? || partial.to_s.strip.empty?

          @last_partial = partial.to_s.strip
          Result.new(
            text: @last_partial,
            partial?: true,
            confidence: nil,
            backend: @backend_name,
            ms: elapsed_ms,
            raw: partial,
          )
        end
      end

      # Close the utterance and return final text (may be empty).
      def finish
        @lock.synchronize do
          return empty_result unless @open

          t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          text, confidence, raw = @backend.finish(@buffer)
          ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round
          @open = false
          @buffer.clear
          Result.new(
            text: text.to_s.strip,
            partial?: false,
            confidence:,
            backend: @backend_name,
            ms:,
            raw:,
          )
        end
      end

      def reset!
        @lock.synchronize do
          @open = false
          @buffer.clear
          @last_partial = ""
          @started_at_ms = nil
          @backend.reset! if @backend.respond_to?(:reset!)
        end
      end

      def snapshot
        @lock.synchronize do
          {
            open: @open,
            backend: @backend_name,
            buffered_samples: @buffer.length,
            last_partial: @last_partial,
          }.freeze
        end
      end

      private

      def empty_result
        Result.new(text: "", partial?: false, confidence: nil, backend: @backend_name, ms: 0, raw: nil)
      end

      def normalize(samples)
        Array(samples).map do |s|
          if s.is_a?(Integer)
            s.clamp(-32_768, 32_767) / 32_768.0
          else
            s.to_f.clamp(-1.0, 1.0)
          end
        end
      end

      def now_ms
        (Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).to_i
      end

      def elapsed_ms
        return 0 unless @started_at_ms

        now_ms - @started_at_ms
      end
    end
  end
end
