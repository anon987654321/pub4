# frozen_string_literal: true
# TODO artifact Z401: Convert all double-escaped heredoc `<<~RUBY` strings in prompts to single-quoted heredocs where interpolation isn't need
module Master
  module Backlog
    module Stubs
      module Z
        class Z401
          ID = "Z401".freeze
          DESCRIPTION = "Convert all double-escaped heredoc `<<~RUBY` strings in prompts to single-quoted heredocs where interpolation isn't needed — prevents accidental interpolation".freeze
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
