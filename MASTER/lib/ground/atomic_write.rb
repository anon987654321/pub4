# frozen_string_literal: true

module Master
  module Ground
    module AtomicWrite
      private

      # Write content to path via tmp+rename. Pass fsync: true for durable config writes.
      def write_atomic(path, content, encoding: "UTF-8", fsync: false)
        tmp_path = "#{path}.tmp.#{Process.pid}"
        File.open(tmp_path, "w", encoding:) do |f|
          f.write(content)
          if fsync
            f.flush
            f.fsync
          end
        end
        File.rename(tmp_path, path)
      rescue StandardError => e
        File.delete(tmp_path) if tmp_path && File.exist?(tmp_path)
        raise e
      end
    end
  end
end
