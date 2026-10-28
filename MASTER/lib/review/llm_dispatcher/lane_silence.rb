# frozen_string_literal: true

require_relative "../../io/lane_silence"

module Master
  module Review
    class LLMDispatcher
      # Io::LaneSilence under the name llm_dispatcher.rb still uses. That file
      # is held by another session; this alias goes when it says Io::LaneSilence.
      LaneSilence = Master::Io::LaneSilence
    end
  end
end
