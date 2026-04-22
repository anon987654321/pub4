# frozen_string_literal: true

module MASTER
  module Stages
    # Stage 3: Block dangerous patterns
    class Guard
      DANGEROUS_PATTERNS = [
        %r{rm\s+-rf?\s+/},
        %r{>\s*/dev/[sh]da},
        /DROP\s+TABLE/i,
        /FORMAT\s+[A-Z]:/i,
        /mkfs\./,
        /dd\s+if=/,
        /chmod\s+[0-7]*7{2,}/,
        /wget\b.+\|\s*(ba)?sh\b/,
        /curl\b.+\|\s*(ba)?sh\b/,
        /\bnc\s.+-e\b/,
      ].freeze

      def call(input)
        if defined?(Logging)
          Logging.dmesg_log("guard0", parent: "pipeline0", message: "ENTER guard",
                                      level: Logging::ALL_EVENTS)
        end
        text = input[:text] || ""
        match = DANGEROUS_PATTERNS.find { |p| p.match?(text) }
        if match
          Result.err("Blocked: dangerous pattern detected.", category: :validation)
        else
          Result.ok(input)
        end
      end
    end
  end
end
