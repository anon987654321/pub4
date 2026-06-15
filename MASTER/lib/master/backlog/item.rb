# frozen_string_literal: true

module Master
  module Backlog
    # Minimal viable backlog item — each TODO ID maps to one artifact with wiring.
    Item = Data.define(:id, :description, :artifact_path, :kind) do
      KINDS = %i[ruby js data yaml].freeze

      def implemented?
        return false unless artifact_path && File.exist?(artifact_path)

        case kind
        when :js
          content = File.read(artifact_path)
          content.include?("implemented: true") || content.include?("IMPLEMENTED")
        else
          true
        end
      end

      def wire!(_container = nil)
        true
      end
    end
  end
end