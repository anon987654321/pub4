# frozen_string_literal: true
# TODO artifact Z304: Replace `defined?(var)` guards with explicit nil check: `defined?(temporary_path)` in ast_fixer.rb — just use `temporary
module Master
  module Backlog
    module Stubs
      module Z
        class Z304
          ID = "Z304".freeze
          DESCRIPTION = "Replace `defined?(var)` guards with explicit nil check: `defined?(temporary_path)` in ast_fixer.rb — just use `temporary_path&.`".freeze
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
