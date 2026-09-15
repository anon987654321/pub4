# frozen_string_literal: true

require_relative "../execution/presence/state"
require_relative "../../review/code_index"

module Master
  module Core
    module Interaction
      # Companion — the bridge between the Omniscient Index and the Presence layer.
      # It projects "Ghost" suggestions to the user based on the current focus of execution.
      class Companion
        attr_reader :index, :bus

        def initialize(index:, event_bus: nil)
          @index = index
          @bus = event_bus
        end

        # Projects ghost suggestions based on the current system state.
        def project(state)
          focus = state.focus
          return [] if focus.nil?

          # 1. Get the symbol details for the current focus
          symbol = index.find(focus)
          return [] if symbol.empty?

          target = symbol.first
          
          # 2. Derive suggestions based on the target
          suggestions = []
          
          # Suggest methods within the same class/module
          if target.type == :class || target.type == :module
            related = index.symbols_in(target.file).select { |s| s.parent == target.fqn }
            related.each do |s|
              suggestions << GhostSuggestion.new(
                symbol: s.fqn,
                location: "#{s.file}:#{s.line}",
                reason: "member of #{target.fqn}"
              )
            end
          end

          # Suggest references (who calls this symbol?)
          impact = index.impact(target.fqn)
          impact[:callers].each do |caller|
            suggestions << GhostSuggestion.new(
              symbol: caller,
              location: caller,
              reason: "calls #{target.fqn}"
            )
          end

          # Publish as an interaction event for the Face to project
          if suggestions.any?
            @bus&.publish("interaction:ghost_suggest", 
              focus: focus, 
              suggestions: suggestions.map(&:to_h)
            )
          end

          suggestions
        end

        # Data structure for a ghost projection.
        GhostSuggestion = Struct.new(:symbol, :location, :reason, keyword_init: true) do
          def to_h
            { symbol: symbol, location: location, reason: reason }
          end
        end
      end
    end
  end
end
