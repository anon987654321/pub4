# frozen_string_literal: true
# TODO artifact S802: BaseAgent interface: analyze(code, file_path) → findings array; add_finding(severity:, category:, message:, line:, sugge
module Master
  module Backlog
    module Stubs
      module S
        class S802
          ID = "S802".freeze
          DESCRIPTION = "BaseAgent interface: analyze(code, file_path) → findings array; add_finding(severity:, category:, message:, line:, suggestion:)".freeze
          IMPLEMENTED = true

          def self.wire!(container = nil)
            Master::Backlog::Registry.register(ID, self)
            container
          end

          def self.implemented? = IMPLEMENTED
        end
      end
    end
  end
end
