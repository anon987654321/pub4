# frozen_string_literal: true

module Commands
  module MiscCommands
    class CinematicPersona
      Result = Struct.new(:ok?, :message, :persona, keyword_init: true)

      def initialize(persona_model: Persona)
        @persona_model = persona_model
      end

      def manage_persona(actor:, target_user:, persona_name:, enable: true)
        return Result.new(ok?: false, message: "Missing target user.") unless target_user
        return Result.new(ok?: false, message: "Missing persona name.") if persona_name.to_s.strip.empty?

        persona = find_persona_for(target_user: target_user, persona_name: persona_name)
        return build_enabled_result(target_user: target_user, persona_name: persona_name) if enable && persona
        return build_disabled_result(target_user: target_user, persona_name: persona_name) unless enable && persona.nil?

        enable ? create_persona(actor: actor, target_user: target_user, persona_name: persona_name) : disable_persona(persona)
      end

      def scan_personas_for(user:)
        @persona_model.includes(:user).where(user_id: user.id).order(created_at: :desc)
      end

      private

      def find_persona_for(target_user:, persona_name:)
        @persona_model.includes(:user).find_by(user_id: target_user.id, name: persona_name)
      end

      def create_persona(actor:, target_user:, persona_name:)
        persona = @persona_model.new(user_id: target_user.id, name: persona_name, created_by_id: actor&.id)

        return Result.new(ok?: true, message: "Persona enabled: #{persona_name}.", persona: persona) if persona.save

        errors = Array(persona.errors&.full_messages).join(", ")
        Result.new(ok?: false, message: "Unable to enable persona: #{errors}.", persona: persona)
      end

      def disable_persona(persona)
        return Result.new(ok?: true, message: "Persona disabled: #{persona.name}.", persona: persona) if persona.destroy

        errors = Array(persona.errors&.full_messages).join(", ")
        Result.new(ok?: false, message: "Unable to disable persona: #{errors}.", persona: persona)
      end

      def build_enabled_result(target_user:, persona_name:)
        Result.new(ok?: true, message: "Persona already enabled for #{target_user.username}: #{persona_name}.")
      end

      def build_disabled_result(target_user:, persona_name:)
        Result.new(ok?: true, message: "Persona not enabled for #{target_user.username}: #{persona_name}.")
      end
    end
  end
end