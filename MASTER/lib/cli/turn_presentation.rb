# frozen_string_literal: true

module Master
  module CLI
    # One user-facing result interpretation for every transport.
    #
    # CLI, web and future adapters may render the envelope differently for their
    # medium, but they never get to invent a different answer for the same Result.
    module TurnPresentation
      ERROR_PREFIX = "ERROR: ".freeze

      module_function

      def text(result)
        return success_text(result) if result.respond_to?(:ok?) && result.ok?
        return error_text(result) if result.respond_to?(:err?) && result.err?

        result.to_s
      end

      def success_text(result)
        value = result.value
        return value.to_s unless value.respond_to?(:[])

        rendered = value[:rendered]
        return rendered.to_s unless rendered.nil? || rendered.to_s.empty?

        output = value[:output]
        return output.to_s unless output.nil? || output.to_s.empty?

        value.to_s
      end

      def error_text(result)
        return result.message.to_s if result.category == :no_api_key

        ERROR_PREFIX + Master::Ground::Redactor.public_error_message
      end
    end
  end
end
