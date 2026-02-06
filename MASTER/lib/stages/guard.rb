# frozen_string_literal: true

module MASTER
  module Stages
    class Guard
      BLOCKED_PATTERNS = [
        /rm\s+-r[f]?\s+\//,
        />\s*\/dev\/[sh]da/,
        /DROP\s+TABLE/i,
        /FORMAT\s+[A-Z]:/i,
        /mkfs\./,
        /dd\s+if=/
      ].freeze

      def call(input)
        # Check if already blocked upstream
        return Result.err("Blocked by upstream") if input[:blocked] || input["blocked"]
        
        text = input[:text] || input["text"] || ""
        
        BLOCKED_PATTERNS.each do |pattern|
          if text.match?(pattern)
            return Result.err("Blocked: potentially destructive command detected")
          end
        end
        
        Result.ok(input)
      end
    end
  end
end
