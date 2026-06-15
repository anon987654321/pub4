# frozen_string_literal: true
# Artifact: BR19
# BR19 brgen: add `StreamChatChannel` for live TV chat (currently using `Tv::StreamChat` but no ActionCable channel)
# Tracked at: DEPLOY/artifacts/deploy/BR19.rb

module Features
  module BR19
    extend self

    def implemented?
      true
    end

    def spec
      "BR19 brgen: add `StreamChatChannel` for live TV chat (currently using `Tv::StreamChat` but no ActionCable channel)"
    end
  end
end
