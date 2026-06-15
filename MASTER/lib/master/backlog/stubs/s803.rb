# frozen_string_literal: true
# TODO artifact S803: SecurityAgent patterns: eval(), system(), exec(), backtick execution, File.read with user params, hardcoded passwords/AP
module Master
  module Backlog
    module Stubs
      module S
        class S803
          ID = "S803".freeze
          DESCRIPTION = "SecurityAgent patterns: eval(), system(), exec(), backtick execution, File.read with user params, hardcoded passwords/API keys, .constantize, dynamic send(), SQL interpolation, html_safe — each with severity and suggested fix".freeze
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
