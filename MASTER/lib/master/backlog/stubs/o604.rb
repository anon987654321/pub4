# frozen_string_literal: true
# TODO artifact O604: repl_loop: @bg_thread&.kill on exit — Thread#kill is unsafe, send a poison-pill message instead
module Master
  module Backlog
    module Stubs
      module O
        class O604
          ID = "O604".freeze
          DESCRIPTION = "repl_loop: @bg_thread&.kill on exit — Thread#kill is unsafe, send a poison-pill message instead".freeze
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
