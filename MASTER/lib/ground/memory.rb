# frozen_string_literal: true

require "yaml"
require "fileutils"
require_relative "memory/store"
require_relative "memory/search"
require_relative "memory/consolidate"

module Master
  module Ground
    # Persistent cross-session memory store with typed entries, recall, and consolidation.
    class Memory
      include Store
      include Search
      include Consolidate

      TTL_DAYS = 90
      CONSOLIDATE_THRESHOLD = 40
      SECONDS_PER_DAY = 86_400
      MAX_INJECT_CONTEXT_RATIO = 100
      MAX_INJECT_TOKEN_CAP = 2_000
      MAX_INJECT_TOKENS = [Master::CTX_WINDOW_SIZE / MAX_INJECT_CONTEXT_RATIO, MAX_INJECT_TOKEN_CAP].min.freeze
      MAX_INJECT_ENTRIES = 5
      TYPES = %w[user feedback project reference general].freeze
      AUTO_SAVE_PATTERNS = {
        "user" => /\b(?:i'?m a|i am a|my role is|i work as)\s+([^.,;\n]{3,80})/i,
        "feedback" => /\b(?:don'?t|stop|never|always|prefer|from now on)\s+([^.,;\n]{3,120})/i,
        "project" => /\b(?:we'?re|deadline|launching|deploying|migrating)\s+([^.,;\n]{3,120})/i,
      }.freeze
    end
  end
end
