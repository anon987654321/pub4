# frozen_string_literal: true

require_relative "../../io/lane_silence"

module Master
  module Review
    class LLMDispatcher
      # Io::LaneSilence under the dispatcher's own name, which llm_dispatcher.rb and
      # the lane tests read; it goes when they say Io::LaneSilence.
      LaneSilence = Master::Io::LaneSilence
    end
  end
end
