# frozen_string_literal: true

require "yaml"

module Master
  module Council
    module Personas
      # veto_role (default false) lets a persona block the pipeline with `VETO:`.
      # Previously Council::Deliberation hardcoded `persona.name == "Security"`,
      # which broke the moment the persona was renamed (e.g. to Norwegian).
      Persona = Data.define(:name, :role, :bias, :prompt, :veto_role) do
        def veto? = veto_role == true
      end

      DEFAULTS = [
        Persona.new(name: "Architect",  role: "System design",   bias: "Structure", prompt: "Review for architectural soundness, coupling, and interface design.", veto_role: false).freeze,
        Persona.new(name: "Skeptic",    role: "Devil advocate",  bias: "Caution",   prompt: "Find what could go wrong. Challenge every assumption.",                veto_role: false).freeze,
        Persona.new(name: "Pragmatist", role: "Implementation",  bias: "Shipping",  prompt: "Is this shippable? Flag over-engineering.",                            veto_role: false).freeze,
        Persona.new(name: "Security",   role: "Security review", bias: "Safety",    prompt: "Find injection vectors, auth bypasses, path traversals. Prefix VETO: if must not ship.", veto_role: true).freeze,
        Persona.new(name: "User",       role: "UX advocate",     bias: "Usability", prompt: "Does this serve the user? Are error messages actionable?",             veto_role: false).freeze,
        Persona.new(name: "Mentor",     role: "Code review",     bias: "Clarity",   prompt: "Is this code readable? Do names reveal intent?",                       veto_role: false).freeze
      ].freeze

      def self.load(data_path = nil)
        return DEFAULTS unless data_path && File.exist?(data_path)
        raw = YAML.safe_load_file(data_path, symbolize_names: true)
        raw.map { |p| Persona.new(**{ veto_role: false }.merge(p)) }
      rescue StandardError
        DEFAULTS
      end
    end
  end
end
