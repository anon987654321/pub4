# frozen_string_literal: true

module Master
  module Ground
    module EnvLoader
      module_function

      def default_paths
        root = defined?(Master::ROOT) ? Master::ROOT : File.expand_path("../..", __dir__)
        [
          "/etc/master.env",
          ENV["MASTER_ENV_FILE"],
          File.expand_path("~/.config/master/env"),
          File.expand_path("~/.master.env"),
          File.expand_path(".master/env", root),
        ].compact.uniq
      end

      def load!(paths: nil)
        loaded = []
        (paths || default_paths).each do |path|
          next unless File.readable?(path)

          apply_file(path)
          loaded << path
        end
        loaded
      end

      def apply_file(path)
        File.foreach(path) do |line|
          stripped = line.strip
          next if stripped.empty? || stripped.start_with?("#")

          key, val = stripped.split("=", 2)
          next unless key && val

          key = key.delete_prefix("export ").strip
          ENV[key] ||= val
        end
      end
    end
  end
end
