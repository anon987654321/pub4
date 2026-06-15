# frozen_string_literal: true
# TODO artifact O208: RuleLoop#scan_files and FixLoop#scan_violations both filter by severity — share SEVERITY_RANK threshold check
module Master
  module Backlog
    module Stubs
      module O
        class O208
          ID = "O208".freeze
          DESCRIPTION = "RuleLoop#scan_files and FixLoop#scan_violations both filter by severity — share SEVERITY_RANK threshold check".freeze
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
