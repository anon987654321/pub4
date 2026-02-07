# frozen_string_literal: true

module MASTER
  module Stages
    # Guard: Block dangerous patterns before they reach the LLM
    class Guard
      DENY = [
        /rm\s+-r[f]?\s+\//,        # rm -rf /
        />\s*\/dev\/[sh]da/,       # > /dev/sda or > /dev/hda
        /DROP\s+TABLE/i,           # DROP TABLE
        /FORMAT\s+[A-Z]:/i,        # FORMAT C:
        /mkfs\./,                  # mkfs.ext4, mkfs.ntfs, etc.
        /dd\s+if=/                 # dd if=/dev/zero, etc.
      ].freeze

      def call(input)
        text = input[:text] || ""
        match = DENY.find { |pattern| pattern.match?(text) }
        
        if match
          Result.err("Blocked: dangerous pattern detected")
        else
          Result.ok(input)
        end
      end
    end
  end
end
