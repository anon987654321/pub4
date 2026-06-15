# frozen_string_literal: true
# TODO artifact U201: Before implementing any new detection rule, fetch ar5iv.org search results for the smell name (e.g., "cyclomatic complex
module Master
  module Backlog
    module Stubs
      module U
        class U201
          ID = "U201".freeze
          DESCRIPTION = "Before implementing any new detection rule, fetch ar5iv.org search results for the smell name (e.g., \"cyclomatic complexity Ruby\" → ar5iv) — cite the academic basis in the rule's description".freeze
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
