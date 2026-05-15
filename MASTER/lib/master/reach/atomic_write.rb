# frozen_string_literal: true

module Master
  module Reach
    module AtomicWrite
      private

      # Write content to path via tmp+rename. Deletes tmp on error.
      def write_atomic(path, content, encoding: "UTF-8")
        tmp_path = "#{path}.tmp.#{Process.pid}"
        File.write(tmp_path, content, encoding:)
        File.rename(tmp_path, path)
      rescue StandardError => e
        File.delete(tmp_path) if tmp_path && File.exist?(tmp_path)
        raise e
      end
    end
  end
end
