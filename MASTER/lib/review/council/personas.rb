# frozen_string_literal: true

module Master
  module Review
    module Council
      module Personas
        Persona = Data.define(:name, :role, :bias, :prompt, :veto_role,
                              :emphasizes, :weight, :aliases, :question, :cognitive_lens, :model) do
          def veto? = veto_role == true
        end

        PERSONA_DEFAULTS = {
          veto_role: false,
          emphasizes: [].freeze,
          weight: 0.05,
          aliases: [].freeze,
          question: nil,
          cognitive_lens: nil,
          model: nil,
        }.freeze

        DEFAULTS = [
          Persona.new(name: "Architect", role: "System design", bias: "Structure",
                      prompt: "Review for architectural soundness, coupling, and interface design.",
                      **PERSONA_DEFAULTS),
          Persona.new(name: "Skeptic", role: "Devil's advocate", bias: "Caution",
                      prompt: "Find what goes wrong. Challenge every assumption.",
                      **PERSONA_DEFAULTS),
          Persona.new(name: "Pragmatist", role: "Implementation", bias: "Shipping",
                      prompt: "Is this shippable? Flag over-engineering.",
                      **PERSONA_DEFAULTS),
          Persona.new(name: "Security", role: "Security review", bias: "Safety",
                      prompt: "Find injection vectors, auth bypasses, path traversals. Prefix VETO: if must not ship.",
                      **PERSONA_DEFAULTS.merge(veto_role: true)),
          Persona.new(name: "User", role: "UX advocate", bias: "Usability",
                      prompt: "Does this serve the user? Are error messages actionable?",
                      **PERSONA_DEFAULTS),
          Persona.new(name: "Mentor", role: "Code review", bias: "Clarity",
                      prompt: "Is this code readable? Do names reveal intent?",
                      **PERSONA_DEFAULTS),
        ].freeze

        persona_members = Persona.members
        ALLOWED_KEYS = persona_members.to_set.freeze

        @cache = {}

        def self.load(data_path = nil)
          path = data_path || Master::COUNCIL_PATH
          return DEFAULTS unless File.exist?(path)

          return @cache[path] if @cache.key?(path)

          begin
            raw = Master.load_yaml(path, symbolize_names: true)
            rows = raw.is_a?(Array) ? raw : Array(raw.fetch(:personas) { raw["personas"] })
            raise "Invalid persona data" unless rows.is_a?(Array) && rows.any?

            @cache[path] = rows.filter_map { |attrs| build_persona(attrs) }.freeze
          rescue StandardError
            DEFAULTS
          end
        end

        def self.build_persona(attrs)
          return unless attrs.is_a?(Hash) && attrs[:name]

          normalised = PERSONA_DEFAULTS.merge(attrs.transform_keys(&:to_sym))
          normalised[:veto_role] = normalised.delete(:can_veto) if normalised.key?(:can_veto)
          normalised = normalised.slice(*ALLOWED_KEYS)
          Persona.new(**normalised)
        end
      end
    end
  end
end
