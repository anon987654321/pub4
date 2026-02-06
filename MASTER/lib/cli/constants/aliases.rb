# frozen_string_literal: true

module MASTER
  class CLI
    module Constants
      module Aliases
        # Command aliases for speed
        ALIASES = {
          'q' => 'queue', 's' => 'scan', 'r' => 'refactor', 'a' => 'ask',
          'c' => 'chamber', 'e' => 'evolve', 'i' => 'introspect', 'p' => 'personas',
          'v' => 'version', 'h' => 'help', '?' => 'help', 'd' => 'diff', 'l' => 'log',
          'st' => 'status', 'hi' => 'history', 'cl' => 'clear'
        }.freeze
      end
    end
  end
end
