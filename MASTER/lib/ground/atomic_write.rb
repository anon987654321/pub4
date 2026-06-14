# frozen_string_literal: true

module Master
  module Ground
    module AtomicWrite
      private

      # Write content to path via tmp+rename. Pass fsync: true for durable config writes.
      def write_atomic(path, content, encoding: "UTF-8", fsync: false)
        temp_path = "#{path}.tmp.#{Process.pid}"
        File.open(temp_path, "w", encoding:) do |f|
          f.write(content)
          if fsync
            f.flush
            f.fsync
          end
        end
        File.rename(temp_path, path)
      rescue StandardError => e
        File.delete(temp_path) if temp_path && File.exist?(temp_path)
        raise e
      end
    end
  end
end
