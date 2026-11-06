# frozen_string_literal: true

module Master
  module Voice
    class Vad
      # Optional Silero ONNX probability backend.
      #
      # Soft-loads the onnxruntime gem and a pinned model path. Returns nil from
      # try_load when either is missing so Vad.build falls back to energy.
      #
      # Contract (16 kHz streaming, Silero v5/v6 style):
      #   input  float32 [1, 512]
      #   state  float32 [2, 1, 128]
      #   sr     int64   scalar 16000
      #   → output float32 [1, 1], stateN float32 [2, 1, 128]
      #
      # Some exports use 576 samples (512 + 64 context). try_load inspects the
      # model input shape when possible; otherwise defaults to 512.
      class SileroBackend
        SAMPLE_RATE = 16_000
        DEFAULT_WINDOW = 512
        STATE_SHAPE = [2, 1, 128].freeze

        def self.try_load(config = {})
          path = model_path(config)
          return unless path && File.file?(path) && File.size?(path)

          require "onnxruntime"
          session = OnnxRuntime::Model.new(path)
          new(session:, path:, config:)
        rescue LoadError, StandardError
          nil
        end

        def self.model_path(config = {})
          env = ENV["MASTER_SILERO_VAD_PATH"].to_s
          return env if !env.empty? && File.file?(env)

          configured = config[:silero_model_path].to_s
          return configured if !configured.empty? && File.file?(configured)

          # Convention relative to MASTER root when loaded from lib/voice/vad/
          candidates = [
            File.expand_path("../../../../vendor/silero/silero_vad.onnx", __dir__),
            File.expand_path("~/.local/share/master/silero_vad.onnx", __dir__),
          ]
          candidates.find { |p| File.file?(p) && File.size?(p) }
        end

        def initialize(session:, path:, config: {})
          @session = session
          @path = path
          @window = detect_window_size(session) || DEFAULT_WINDOW
          @state = zero_state
          @ring = []
        end

        def name = :silero

        def reset!
          @state = zero_state
          @ring.clear
        end

        # Accumulate samples until one Silero window is full, then score.
        # Between windows, return the last probability (0.0 after reset).
        def score(floats, rms: nil)
          @ring.concat(Array(floats))
          probability = @last_probability || 0.0

          while @ring.length >= @window
            chunk = @ring.shift(@window)
            probability = infer(chunk)
            @last_probability = probability
          end

          probability
        end

        attr_reader :path, :window

        private

        def detect_window_size(session)
          inputs = session.inputs
          audio = inputs.find { |i| i[:name].to_s =~ /input|audio/i } || inputs.first
          shape = audio && (audio[:shape] || audio["shape"])
          return unless shape.is_a?(Array) && shape.length >= 2

          dim = shape.last
          dim.is_a?(Integer) && dim.positive? ? dim : nil
        rescue StandardError
          nil
        end

        def zero_state
          # [2, 1, 128] nested arrays for onnxruntime ruby
          Array.new(2) { Array.new(1) { Array.new(128, 0.0) } }
        end

        def infer(chunk)
          # Pad if somehow short (should not happen after ring gate)
          if chunk.length < @window
            chunk = chunk + Array.new(@window - chunk.length, 0.0)
          end
          input = [chunk.map(&:to_f)] # [1, window]

          feeds = build_feeds(input)
          outputs = @session.predict(feeds)
          probability, next_state = extract_outputs(outputs)
          @state = next_state if next_state
          probability.to_f.clamp(0.0, 1.0)
        rescue StandardError
          0.0
        end

        def build_feeds(input)
          names = @session.inputs.map { |i| i[:name].to_s }
          feed = {}
          feed[names.find { |n| n =~ /input|audio/i } || names[0]] = input
          state_name = names.find { |n| n =~ /state/i }
          feed[state_name] = @state if state_name
          sr_name = names.find { |n| n =~ /\bsr\b/i }
          feed[sr_name] = [SAMPLE_RATE] if sr_name
          feed
        end

        def extract_outputs(outputs)
          # predict may return Hash of name => value
          if outputs.is_a?(Hash)
            prob_key = outputs.keys.find { |k| k.to_s =~ /output|prob/i } || outputs.keys.first
            state_key = outputs.keys.find { |k| k.to_s =~ /stateN|state_n|hn|cn/i }
            prob = unwrap_scalar(outputs[prob_key])
            state = state_key ? outputs[state_key] : nil
            [prob, state]
          elsif outputs.is_a?(Array)
            [unwrap_scalar(outputs[0]), outputs[1]]
          else
            [0.0, nil]
          end
        end

        def unwrap_scalar(value)
          case value
          when Numeric then value
          when Array
            current = value
            current = current[0] while current.is_a?(Array) && current.length == 1
            current.is_a?(Numeric) ? current : current.to_f
          else
            value.to_f
          end
        end
      end
    end
  end
end
