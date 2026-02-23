# frozen_string_literal: true

require "yaml"

module MASTER
  module Analysis
    # Validates OpenBSD daemon config files against rules from data/platform.yml.
    # Used by prescan and by the shell_command tool when it detects a .conf file path.
    module OpenBSDConfigValidator
      extend self

      PATTERNS_FILE = File.join(MASTER.root, "data", "platform.yml")

      def rules
        @rules ||= begin
          YAML.safe_load_file(PATTERNS_FILE)&.dig("config_validation") || {}
        rescue StandardError
          {}
        end
      end

      # Validate a config file by name. Returns array of issue hashes.
      # @param filename [String] basename like "pf.conf" or "sshd_config"
      # @param content  [String] file content to validate
      # @return [Array<Hash>] [{severity:, message:, daemon:, man:}]
      def validate(filename, content)
        rule = rules[File.basename(filename)]
        return [] unless rule

        issues = []
        daemon = rule["daemon"]
        man    = rule["man"]

        (rule["required_patterns"] || []).each do |pat|
          unless content.include?(pat)
            issues << {
              severity: :error,
              daemon:   daemon,
              man:      man,
              message:  "#{filename}: missing required pattern: #{pat.inspect}  (see man #{man})",
            }
          end
        end

        (rule["warnings"] || []).each do |w|
          pat = w["pattern"]
          if w["absent_message"] && pat && !content.match?(/#{Regexp.escape(pat)}/i)
            issues << { severity: :warn, daemon: daemon, man: man,
                        message: "#{filename}: #{w['absent_message']}" }
          elsif w["message"] && pat && content.match?(/#{Regexp.escape(pat)}/i)
            issues << { severity: :warn, daemon: daemon, man: man,
                        message: "#{filename}: #{w['message']}" }
          end
        end

        issues
      end

      # Scan a directory for known OpenBSD config files and validate each.
      def scan_dir(dir = "/etc")
        results = {}
        rules.each_key do |filename|
          path = File.join(dir, filename)
          next unless File.readable?(path)

          content = File.read(path)
          issues = validate(filename, content)
          results[filename] = issues if issues.any?
        end
        results
      end
    end
  end
end
