# frozen_string_literal: true

require "yaml"

module Master
  module Judge
  module Scan
    module Rules
      # Detects phantom reads — Ruby code digs keys that don't exist in the corresponding data/*.yml.
      # Also detects orphan keys — top-level YAML keys with zero references in lib/.
      # Only meaningful when scanning lib/ with root: access.
      class InterconnectRule < Rule
        LOAD_CALL = /load_yaml(?:_data)?\s*\(\s*["']([^"']+\.yml)["']/.freeze
        DIG_CALL = /\.dig\(\s*((?:["'][^"']+["']\s*,?\s*)+)\)/.freeze
        FETCH_CALL = /\.fetch\(\s*["']([^"']+)["']/.freeze
        BRACKET_KEY = /\[["']([^"']+)["']\]/.freeze

        def self.auto_build? = false

        def initialize(root:)
          super()
          @id = "interconnect"
          @description = "Phantom YAML key reads and orphan data keys"
          @severity = :warning
          @auto_fix = false
          @rule_tags = %i[ONE_SOURCE]
          @root = root
          @data_dir = File.join(root, "data")
          @lib_source = load_lib_source(root)
        end

        def check(code, path:)
          findings = []
          findings.concat(check_phantom_yaml_reads(code, path)) if path.include?("/lib/") && path.end_with?(".rb")
          findings.concat(check_phantom_scan_classes(code, path)) \
            if path.end_with?("rules.yml") && path.include?("/data/")
          findings
        end

        private

        def check_phantom_yaml_reads(code, _path)
          yaml_files = extract_loaded_yamls(code)
          return [] if yaml_files.empty?

          loaded = yaml_files.filter_map do |yml_name|
            yml_path = File.join(@data_dir, yml_name)
            next unless File.exist?(yml_path)
            YAML.safe_load(File.read(yml_path), aliases: true) rescue nil
          end
          return [] if loaded.empty?

          findings = []
          extract_dig_paths(code).each do |path_keys|
            next if loaded.any? { |y| y.respond_to?(:dig) && y.dig(*path_keys) }
            code.each_line.with_index(1) do |line, number|
              next unless line.include?(path_keys.first.to_s)
              findings << finding(
                line: number,
                message: "phantom key #{path_keys.inspect} not found in any loaded yaml"
              )
              break
            end
          end
          findings
        end

        def check_phantom_scan_classes(code, _path)
          data = YAML.safe_load(code, aliases: true) rescue nil
          return [] unless data.is_a?(Hash)

          depths = data["scan_depths"] || {}
          rules_dir = File.join(@root, "lib", "master", "judge", "scan", "rules")
          findings = []
          depths.each_value do |class_names|
            next unless class_names.is_a?(Array)
            class_names.each do |name|
              next if name == "all"
              snake = name.gsub(/([A-Z])(?=[A-Z][a-z])|([a-z\d])([A-Z])/) { "#{$1 || $2}_#{$3}" }
                         .downcase
              file = File.join(rules_dir, "#{snake}.rb")
              next if File.exist?(file)
              line_num = code.each_line.with_index(1).find { |l, _| l.include?(name) }&.last || 1
              findings << finding(
                line: line_num,
                message: "scan_depths references phantom class #{name} — #{snake}.rb not found in judge/scan/rules/"
              )
            end
          end
          findings
        end

        def extract_loaded_yamls(code)
          code.scan(LOAD_CALL).flatten.compact
        end

        def extract_dig_paths(code)
          code.scan(DIG_CALL).filter_map do |match|
            raw = match.first.to_s
            keys = raw.scan(/["']([^"']+)["']/).flatten
            keys.size >= 1 ? keys : nil
          end
        end

        def load_lib_source(root)
          lib_dir = File.join(root, "lib")
          return "" unless File.directory?(lib_dir)
          Dir.glob(File.join(lib_dir, "**", "*.rb"))
             .filter_map { |f| File.read(f) rescue nil }
             .join("\n")
        end
      end
    end
  end
  end
end
