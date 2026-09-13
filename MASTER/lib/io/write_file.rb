# frozen_string_literal: true

require "fileutils"

module Master
  module Io
    class WriteFile
      include Base
      TIER = :guarded
      NAME = "write_file".freeze
      DESCRIPTION = "Atomically write content to a file, with undo snapshot.".freeze

      def initialize(root:, undo:, governor:, event_bus: nil, diff_stager: nil, ground_truth: nil)
        @root, @undo, @governor, @bus, @diff_stager, @ground_truth =
          File.realpath(root), undo, governor, event_bus, diff_stager, ground_truth
      end

      # A whole-file write replaces whatever is on disk, so a file that changed
      # after this session read it is refused: the write was composed against
      # bytes that are gone, and the change it would discard was never seen.
      # StrReplace needs no such check, because it matches against the file as
      # it is when it runs.
      def call(path:, content:)
        safely do
          resolved = resolve(path)
          next resolved if resolved.err?

          full = resolved.value!
          next stale_read(path, full) if @ground_truth&.changed_since_read?(full)

          perm = permit(path)
          next perm if perm.err?

          FileUtils.mkdir_p(File.dirname(full))
          commit_write(full, content, path:)
        end
      end

      private

      def stale_read(path, full)
        @bus&.publish("ground_truth:stale", path: full, reason: "write_file")
        Result.err("write refused — #{path} changed since it was read; read it again", category: :policy)
      end
    end
  end
end
