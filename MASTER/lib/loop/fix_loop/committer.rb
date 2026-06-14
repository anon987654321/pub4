# frozen_string_literal: true

module Master
  module Loop
    class FixLoop
      class Committer
        def initialize(git:, bus: nil)
          @git = git
          @bus = bus
        end

        def commit_if_dirty(message)
          return unless @git&.dirty?(".")

          @git.add_all
          @git.commit(message)
        rescue StandardError => e
          @bus&.publish("fix_loop:commit_error", error: e.message)
        end
      end
    end
  end
end
