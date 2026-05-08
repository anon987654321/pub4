# frozen_string_literal: true

require "fileutils"

module Master
  module Tools
    class WriteFile
      include Base
      TIER        = :guarded
      NAME        = "write_file".freeze
      DESCRIPTION = "Atomically write content to a file, with undo snapshot.".freeze

      def initialize(root:, undo:, governor:, event_bus: nil, diff_stager: nil)
        @root, @undo, @governor, @bus, @diff_stager =
          File.realpath(root), undo, governor, event_bus, diff_stager
      end

      def call(path:, content:)
        safely do
          resolved = resolve(path)
          next resolved if resolved.err?

          full = resolved.value!
          perm = permit(path)
          next perm if perm.err?

          FileUtils.mkdir_p(File.dirname(full))
          commit_write(full, content, path:)
        end
      end
    end
  end
end
