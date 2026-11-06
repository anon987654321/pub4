# frozen_string_literal: true

module Master
  module Voice
    class Stt
      # Binds Vad events to Stt utterance lifecycle and delivers final text
      # to a callback (typically Session → agent). Keeps modules decoupled.
      module SessionBridge
        module_function

        def attach(vad, stt, on_final: nil)
          raise ArgumentError, "vad required" unless vad
          raise ArgumentError, "stt required" unless stt

          vad.on_event do |event|
            case event.name
            when :speech_start
              stt.start_utterance(at_ms: event.at_ms)
            when :speech_end
              result = stt.finish
              on_final&.call(result) if result && !result.text.empty?
            end
          end

          stt
        end
      end
    end
  end
end
