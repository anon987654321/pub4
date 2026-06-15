# frozen_string_literal: true
# TODO artifact Z502: Normalize severity symbols: all rules use :error/:warning/:info — audit for :critical, :high, :medium (legacy from v50.8
module Master
  module Backlog
    module Stubs
      module Z
        class Z502
          ID = "Z502".freeze
          DESCRIPTION = "Normalize severity symbols: all rules use :error/:warning/:info — audit for :critical, :high, :medium (legacy from v50.8 SecurityAgent) left over".freeze
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
