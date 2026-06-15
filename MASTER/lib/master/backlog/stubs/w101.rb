# frozen_string_literal: true
# TODO artifact W101: Codify unix-silence rule: "silence on success, text only when something noteworthy" — add as `unix_silence: true` in sou
module Master
  module Backlog
    module Stubs
      module W
        class W101
          ID = "W101".freeze
          DESCRIPTION = "Codify unix-silence rule: \"silence on success, text only when something noteworthy\" — add as `unix_silence: true` in soul.yml absolute.aesthetic_rules; CLI scan with zero findings exits 0 with no output".freeze
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
