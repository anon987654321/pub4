# frozen_string_literal: true

module Master
  module Ground
    module EnvLoader
      module_function

      # MASTER_NO_ENV_FILES=1 reads only a file MASTER_ENV_FILE names: the suite
      # sets it so a key in the operator's ~/.config/master/env cannot decide
      # which lane a test routes to.
      def default_paths
        return [ENV["MASTER_ENV_FILE"]].compact if ENV["MASTER_NO_ENV_FILES"] == "1"

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
          ENV[key] ||= unquote(val.strip)
        end
      end

      # The same files are sourced by sh (rc.d/master), where KEY="value" is the
      # usual spelling; the quotes are shell syntax, not part of the value.
      def unquote(value)
        quoted = value.length >= 2 && %w[" '].include?(value[0]) && value[-1] == value[0]
        quoted ? value[1...-1] : value
      end
    end
  end
end
