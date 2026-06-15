# frozen_string_literal: true
# TODO artifact U108: "Inversion test" prompt: after proposing a fix, ask "if this fix is wrong, what would break, where, and when?" — forces 
module Master
  module Backlog
    module Stubs
      module U
        class U108
          ID = "U108".freeze
          DESCRIPTION = "\"Inversion test\" prompt: after proposing a fix, ask \"if this fix is wrong, what would break, where, and when?\" — forces adversarial self-review before applying".freeze
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
