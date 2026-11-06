# frozen_string_literal: true

require "monitor"
require_relative "vad/energy_backend"

module Master
  module Voice
    # Frame-level voice activity detection for the eyes-free loop.
    #
    # This is the sensor behind Session: it decides speech_start and speech_end
    # from PCM frames. It does not own the mic, STT, or TTS.
    #
    # Default backend is pure energy (RMS) with hysteresis — zero native deps,
    # OpenBSD-safe, fully fixture-testable. Silero ONNX is an optional backend
    # loaded when the model and onnxruntime are present; missing pieces fall
    # back to energy without changing the public events.
    #
    # Policy is asymmetric: false positives (cutting the user off) are worse
    # than false negatives (a short lag). Barge-in uses a higher bar.
    class Vad
      SAMPLE_RATE = 16_000
      # Energy path uses 30 ms; Silero wants 32 ms / 512 samples. The process
      # method accepts either and the active backend documents its window.
      FRAME_MS = 30
      FRAME_SAMPLES = (SAMPLE_RATE * FRAME_MS / 1000.0).round # 480

      DEFAULTS = {
        speech_threshold: 0.45,
        silence_threshold: 0.30,
        min_speech_ms: 250,
        hangover_ms: 700,
        barge_speech_threshold: 0.60,
        barge_min_speech_ms: 350,
        energy_floor: 0.008,
        energy_ceiling: 0.25,
        backend: :auto, # :auto | :energy | :silero
      }.freeze

      Frame = Data.define(:speech?, :probability, :rms, :at_ms, :backend)
      Event = Data.define(:name, :at_ms, :mode, :probability, :rms)

      attr_reader :speaking, :mode, :config, :backend_name

      def self.build(config: {})
        cfg = DEFAULTS.merge(config.transform_keys(&:to_sym))
        backend = resolve_backend(cfg)
        new(backend:, config: cfg)
      end

      def self.resolve_backend(cfg)
        choice = cfg[:backend].to_sym
        case choice
        when :energy
          EnergyBackend.new(cfg)
        when :silero
          silero = try_silero(cfg)
          raise LoadError, "Silero VAD requested but unavailable" unless silero

          silero
        else # :auto
          try_silero(cfg) || EnergyBackend.new(cfg)
        end
      end
      private_class_method :resolve_backend

      def self.try_silero(cfg)
        require_relative "vad/silero_backend"
        SileroBackend.try_load(cfg)
      rescue LoadError, StandardError
        nil
      end
      private_class_method :try_silero

      def initialize(backend: nil, config: {}, clock_ms: -> { (Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).to_i })
        @lock = Monitor.new
        @config = DEFAULTS.merge(config.transform_keys(&:to_sym))
        @backend = backend || EnergyBackend.new(@config)
        @backend_name = @backend.name
        @clock_ms = clock_ms
        @mode = :listening # :listening | :barge_in
        @speaking = false
        @speech_started_at = nil
        @silence_started_at = nil
        @last_probability = 0.0
        @last_rms = 0.0
        @listeners = []
        @frame_index = 0
      end

      def on_event(&block)
        @lock.synchronize { @listeners << block }
        self
      end

      def mode!(next_mode)
        mode = next_mode.to_sym
        raise ArgumentError, "unknown VAD mode: #{mode}" unless %i[listening barge_in].include?(mode)

        @lock.synchronize { @mode = mode }
        mode
      end

      def reset!
        @lock.synchronize do
          @speaking = false
          @speech_started_at = nil
          @silence_started_at = nil
          @last_probability = 0.0
          @last_rms = 0.0
          @backend.reset! if @backend.respond_to?(:reset!)
        end
      end

      # Process one mono PCM frame.
      # samples: Enumerable of Float [-1, 1] or Integer PCM16.
      # Returns a Frame; may emit :speech_start / :speech_end events.
      def process(samples, at_ms: nil)
        now = at_ms || @clock_ms.call
        floats = normalize_samples(samples)
        rms = rms_of(floats)
        probability = @backend.score(floats, rms:)

        @lock.synchronize do
          @last_rms = rms
          @last_probability = probability
          @frame_index += 1
          apply_hysteresis!(probability, rms, now)
          Frame.new(
            speech?: @speaking,
            probability:,
            rms:,
            at_ms: now,
            backend: @backend_name,
          )
        end
      end

      def snapshot
        @lock.synchronize do
          {
            speaking: @speaking,
            mode: @mode,
            probability: @last_probability,
            rms: @last_rms,
            frame_index: @frame_index,
            backend: @backend_name,
          }.freeze
        end
      end

      private

      def apply_hysteresis!(probability, rms, now)
        speech_gate = threshold_for_speech
        silence_gate = @config[:silence_threshold]
        min_speech = min_speech_for_mode
        hangover = @config[:hangover_ms]

        if probability >= speech_gate
          @silence_started_at = nil
          if @speech_started_at.nil?
            @speech_started_at = now
          elsif !@speaking && (now - @speech_started_at) >= min_speech
            @speaking = true
            emit!(:speech_start, at_ms: now, probability:, rms:)
          end
        elsif probability < silence_gate
          @speech_started_at = nil unless @speaking
          if @speaking
            @silence_started_at ||= now
            if (now - @silence_started_at) >= hangover
              @speaking = false
              @silence_started_at = nil
              emit!(:speech_end, at_ms: now, probability:, rms:)
            end
          end
        else
          # Hysteresis band: hold decision; do not start silence clock.
          @silence_started_at = nil if @speaking
        end
      end

      def threshold_for_speech
        @mode == :barge_in ? @config[:barge_speech_threshold] : @config[:speech_threshold]
      end

      def min_speech_for_mode
        @mode == :barge_in ? @config[:barge_min_speech_ms] : @config[:min_speech_ms]
      end

      def normalize_samples(samples)
        Array(samples).map do |s|
          if s.is_a?(Integer)
            s.clamp(-32_768, 32_767) / 32_768.0
          else
            s.to_f.clamp(-1.0, 1.0)
          end
        end
      end

      def rms_of(floats)
        return 0.0 if floats.empty?

        Math.sqrt(floats.sum { |x| x * x } / floats.length)
      end

      def emit!(name, at_ms:, probability:, rms:)
        event = Event.new(name: name.to_sym, at_ms:, mode: @mode, probability:, rms:)
        @listeners.each do |listener|
          listener.call(event)
        rescue StandardError => e
          if defined?(Master::Ground::Swallow)
            Master::Ground::Swallow.log(e, context: "Voice::Vad.on_event")
          end
        end
        event
      end
    end
  end
end
