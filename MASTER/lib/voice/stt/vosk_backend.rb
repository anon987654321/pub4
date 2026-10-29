# frozen_string_literal: true

module Master
  module Voice
    class Stt
      # Optional Vosk offline recognizer. Soft-loads the vosk gem.
      #
      # Streaming: feed() may return partial text. finish() returns final.
      # Grammar: pass config[:grammar] as Array of phrases for APPROVAL turns.
      class VoskBackend
        def self.try_load(config = {})
          path = model_path(config)
          return unless path && File.directory?(path)

          require "vosk"
          model = Vosk::Model.new(model_path: path)
          new(model:, config:)
        rescue LoadError, StandardError
          nil
        end

        def self.model_path(config = {})
          env = ENV["MASTER_VOSK_MODEL"].to_s
          return env if !env.empty? && File.directory?(env)

          configured = config[:vosk_model_path].to_s
          return configured if !configured.empty? && File.directory?(configured)

          candidates = [
            File.expand_path("../../../../vendor/vosk/model", __dir__),
            File.expand_path("~/.local/share/master/vosk-model-small-en-us", __dir__),
            File.expand_path("~/.cache/vosk/vosk-model-small-en-us-0.15", __dir__),
          ]
          candidates.find { |p| File.directory?(p) }
        end

        def initialize(model:, config: {})
          @model = model
          @sample_rate = (config[:sample_rate] || Stt::SAMPLE_RATE).to_i
          @grammar = config[:grammar]
          @recognizer = nil
        end

        def name = :vosk

        def start_utterance
          @recognizer = build_recognizer
        end

        def feed(floats)
          return unless @recognizer

          pcm = floats_to_pcm16(floats)
          if @recognizer.accept_waveform(pcm).nonzero?
            parse_text(@recognizer.result)
          else
            parse_partial(@recognizer.partial_result)
          end
        rescue StandardError
          nil
        end

        def finish(_floats)
          return ["", nil, nil] unless @recognizer

          raw = @recognizer.final_result
          text = parse_text(raw)
          [text, nil, raw]
        rescue StandardError
          ["", nil, nil]
        ensure
          @recognizer = nil
        end

        def reset!
          @recognizer = nil
        end

        private

        def build_recognizer
          if @grammar.is_a?(Array) && !@grammar.empty?
            require "json"
            grammar_json = JSON.generate(@grammar.map(&:to_s) + ["[unk]"])
            Vosk::KaldiRecognizer.new(@model, @sample_rate, grammar_json)
          else
            Vosk::KaldiRecognizer.new(@model, @sample_rate)
          end
        end

        def floats_to_pcm16(floats)
          floats.map { |f| (f * 32_767).round.clamp(-32_768, 32_767) }.pack("s<*")
        end

        def parse_text(json_str)
          require "json"
          h = JSON.parse(json_str.to_s)
          (h["text"] || h[:text] || "").to_s.strip
        rescue StandardError
          ""
        end

        def parse_partial(json_str)
          require "json"
          h = JSON.parse(json_str.to_s)
          t = (h["partial"] || h[:partial] || "").to_s.strip
          t.empty? ? nil : t
        rescue StandardError
          nil
        end
      end
    end
  end
end
