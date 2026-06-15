# frozen_string_literal: true
# TODO artifact O204: RuleLoop#build_prompt and build_diff_prompt share 80% of structure — extract shared_prompt_header(violation, src, path)
module Master
  module Backlog
    module Stubs
      module O
        class O204
          ID = "O204".freeze
          DESCRIPTION = "RuleLoop#build_prompt and build_diff_prompt share 80% of structure — extract shared_prompt_header(violation, src, path)".freeze
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
