# frozen_string_literal: true

module Master
  module Tools
    module AtomicWrite
      private

      # Write content to path via tmp+rename. Deletes tmp on error.
      def write_atomic(path, content, encoding: "UTF-8")
        tmp = "#{path}.tmp.#{Process.pid}"
        File.write(tmp, content, encoding:)
        File.rename(tmp, path)
      rescue StandardError
        File.delete(tmp) if tmp && File.exist?(tmp)
        raise
      end
    end
  end
end
