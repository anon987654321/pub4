# frozen_string_literal: true

module Master
  module Voice
    class Stt
      # Always available. Returns empty text. Keeps the loop honest when no STT
      # runtime is installed (OpenBSD, CI, first boot).
      class NullBackend
        def name = :null

        def start_utterance; end

        def feed(_floats) = nil

        def finish(_floats) = ["", nil, nil]

        def reset!; end
      end
    end
  end
end
