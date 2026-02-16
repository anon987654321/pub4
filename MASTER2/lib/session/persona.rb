# frozen_string_literal: true

module MASTER
  class Session
    # Persona management
    module Persona
      extend self

      # Set current persona
      def set_persona(persona)
        # Load available personas from constitution.yml
        constitution_file = File.join(MASTER.root, "data", "constitution.yml")
        if File.exist?(constitution_file)
          constitution = YAML.safe_load_file(constitution_file, symbolize_names: true)
          available_personas = constitution.dig(:personas, :available)&.keys || [:ronin]
          return Result.err("Unknown persona: #{persona}") unless available_personas.include?(persona.to_sym)
        end

        Session.current.write_metadata(:persona, persona)
        Result.ok(persona: persona)
      end

      def current_persona
        Session.current.metadata_value(:persona) || :ronin
      end
    end
  end
end
