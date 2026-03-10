# frozen_string_literal: true

require "yaml"

module Master3
  module Council
    Persona = Data.define(:name, :role, :bias, :prompt)

    DEFAULTS = [
      Persona.new(name: "Architect",   role: "System design",        bias: "Structure",  prompt: "Review for architectural soundness, coupling, and interface design."),
      Persona.new(name: "Skeptic",     role: "Devils advocate",      bias: "Caution",    prompt: "Find what could go wrong. Challenge every assumption. Play adversarial."),
      Persona.new(name: "Pragmatist",  role: "Implementation",       bias: "Shipping",   prompt: "Is this shippable? What is the minimum viable version? Flag over-engineering."),
      Persona.new(name: "Security",    role: "Security review",      bias: "Safety",     prompt: "Find injection vectors, auth bypasses, path traversals, unsafe operations."),
      Persona.new(name: "User",        role: "UX advocate",          bias: "Usability",  prompt: "Does this serve the user? Is it clear? Are error messages actionable?"),
      Persona.new(name: "Mentor",      role: "Code review",          bias: "Clarity",    prompt: "Is this code readable? Does it follow conventions? Are names clear?")
    ].freeze

    def self.load(data_path = nil)
      return DEFAULTS unless data_path && File.exist?(data_path)
      YAML.safe_load_file(data_path, symbolize_names: true).map { |p|
        Persona.new(**p)
      }
    rescue StandardError
      DEFAULTS
    end
  end
end
