# frozen_string_literal: true
# AN619: Music discovery (demo/fallback)

module Playlist
  class MusicDiscovery
    def initialize(user)
      @user = user
    end

    def suggestions
      if ENV["LLM_MUSIC_ENABLED"] == "true" && defined?(RubyLLM)
        RubyLLM.chat("Suggest 10 artists similar to #{listening_history}").to_s.split("\n").first(10)
      else
        %w[Aurora Sigrid Girl in Red A-ha Kings of Convenience Röyksopp Datarock Madrugada Highasakite Sondre Lerche]
      end
    end

    private

    def listening_history
      Listen.order(created_at: :desc).limit(5).pluck(:track_name).join(", ")
    rescue NameError
      "Norwegian indie"
    end
  end
end