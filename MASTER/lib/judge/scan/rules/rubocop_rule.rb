# frozen_string_literal: true

require "open3"
require "json"

module Master
  module Judge
  module Scan
    module Rules
      class RubocopRule < Rule
        def self.auto_build? = false

        def initialize(root:)
          super()
          @id = "rubocop"
          @description = "RuboCop style/lint violation"
          @severity = :warning
          @auto_fix = false
          @rule_tags = %i[STYLE LINT]
          @root = root
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb") && rubocop_available?

          stdout, _stderr, status = Open3.capture3(
            Master::BUNDLE_BIN, "exec", "rubocop", "--format", "json", "--no-color", path,
            chdir: @root
          )
          return [] if stdout.empty?

          data = begin; JSON.parse(stdout); rescue JSON::ParserError; return []; end
          offenses = data.dig("files", 0, "offenses") || []
          offenses.map do |o|
            finding(
              line: o.dig("location", "line") || 1,
              message: "rubocop: #{o["cop_name"]} — #{o["message"]}"
            )
          end
        rescue StandardError => e
          [finding(line: 1, message: "rubocop: scan error — #{e.message}")]
        end

        private

        def rubocop_available?
          system("which rubocop > /dev/null 2>&1") ||
            File.exist?(File.join(@root, "bin", "rubocop"))
        end
      end
    end
  end
  end
end
