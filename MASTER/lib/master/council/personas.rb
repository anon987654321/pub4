# frozen_string_literal: true

require "yaml"

module Master
  module Council
    module Personas
      Persona = Data.define(:name, :role, :bias, :prompt)

      DEFAULTS = [
        Persona.new(name: "Architect",  role: "System design",    bias: "Structure", prompt: "Review for architectural soundness, coupling, and interface design."),
        Persona.new(name: "Skeptic",    role: "Devil advocate",   bias: "Caution",   prompt: "Find what could go wrong. Challenge every assumption."),
        Persona.new(name: "Pragmatist", role: "Implementation",   bias: "Shipping",  prompt: "Is this shippable? Flag over-engineering."),
        Persona.new(name: "Security",   role: "Security review",  bias: "Safety",    prompt: "Find injection vectors, auth bypasses, path traversals. Prefix VETO: if must not ship."),
        Persona.new(name: "User",       role: "UX advocate",      bias: "Usability", prompt: "Does this serve the user? Are error messages actionable?"),
        Persona.new(name: "Mentor",     role: "Code review",      bias: "Clarity",   prompt: "Is this code readable? Do names reveal intent?")
      ].freeze

      def self.load(data_path = nil)
        return DEFAULTS unless data_path && File.exist?(data_path)
        YAML.safe_load_file(data_path, symbolize_names: true).map { |p| Persona.new(**p) }
      rescue StandardError
        DEFAULTS
      end
    end
  end
end
