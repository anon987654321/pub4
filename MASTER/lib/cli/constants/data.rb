# frozen_string_literal: true

module MASTER
  class CLI
    module Constants
      module Data
        # Boot quotes (rotates each session)
        QUOTES = [
          "Simplicity is the ultimate sophistication.",
          "Make it work, make it right, make it fast.",
          "Code is read more often than written.",
          "The best code is no code at all.",
          "Clarity over cleverness.",
          "Ship it.",
          "Done is better than perfect.",
          "Constraints breed creativity.",
          "Less, but better.",
          "If in doubt, leave it out."
        ].freeze

        # Session name parts
        ADJECTIVES = %w[crimson azure golden silent swift keen bright calm deep iron].freeze
        NOUNS = %w[falcon raven wolf oak storm forge arrow tide spark blade].freeze

        # Easter eggs (1% chance)
        EGGS = [
          "The machine spirit is pleased.",
          "Consulting the oracle...",
          "Reticulating splines..."
        ].freeze
      end
    end
  end
end
