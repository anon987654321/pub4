# frozen_string_literal: true

module Master
  module Council
    module Personas
      Persona = Data.define(:name, :role, :bias, :prompt, :veto_role) do
        def veto? = veto_role == true
      end

      DEFAULTS = [
        Persona.new(name: "Architect",  role: "System design",   bias: "Structure",
                    prompt: "Review for architectural soundness, coupling, and interface design.", veto_role: false),
        Persona.new(name: "Skeptic",    role: "Devil's advocate", bias: "Caution",
                    prompt: "Find what could go wrong. Challenge every assumption.", veto_role: false),
        Persona.new(name: "Pragmatist", role: "Implementation",  bias: "Shipping",
                    prompt: "Is this shippable? Flag over-engineering.", veto_role: false),
        Persona.new(name: "Security",   role: "Security review", bias: "Safety",
                    prompt: "Find injection vectors, auth bypasses, path traversals. Prefix VETO: if must not ship.", veto_role: true),
        Persona.new(name: "User",       role: "UX advocate",     bias: "Usability",
                    prompt: "Does this serve the user? Are error messages actionable?", veto_role: false),
        Persona.new(name: "Mentor",     role: "Code review",     bias: "Clarity",
                    prompt: "Is this code readable? Do names reveal intent?", veto_role: false)
      ].freeze

      @cache = {}

      def self.load(data_path = nil)
        return DEFAULTS if data_path.nil? || !File.exist?(data_path)

        @cache[data_path] ||= begin
          raw = Master.load_yaml(data_path, symbolize_names: true)
          raise "Invalid persona data" unless raw.is_a?(Array)

          raw.map do |attrs|
            raise "Persona must be a hash" unless attrs.is_a?(Hash)

            attrs = { veto_role: false }.merge(attrs)
            Persona.new(**attrs)
          end.freeze
        rescue StandardError
          DEFAULTS
        end
      end
    end
  end
end