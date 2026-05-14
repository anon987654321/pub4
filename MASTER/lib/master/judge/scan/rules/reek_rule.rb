# frozen_string_literal: true

require "open3"
require "json"

module Master
  module Judge
  module Scan
    module Rules
      # Runs Reek on .rb files and surfaces code smell violations.
      class ReekRule < Rule
        def self.auto_build? = false

        def initialize(root:)
          super()
          @id          = "reek"
          @description = "Reek code smell detected"
          @severity    = :warning
          @auto_fix    = false
          @rule_tags  = %i[SMELL ONE_JOB]
          @root        = root
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb") && reek_available?

          stdout, _stderr, _status = Open3.capture3(
            "bundle", "exec", "reek", "--format", "json", path,
            chdir: @root
          )
          return [] if stdout.empty?

          smells = JSON.parse(stdout) rescue return []
          smells.flat_map do |smell|
            locations = smell["lines"] || [1]
            locations.map do |line|
              finding(
                line:    line,
                message: "reek: #{smell["smell_type"]} — #{smell["message"]}"
              )
            end
          end
        rescue StandardError => e
          [finding(line: 1, message: "reek: scan error — #{e.message}")]
        end

        private

        def reek_available?
          system("which reek > /dev/null 2>&1") ||
            File.exist?(File.join(@root, "bin", "reek"))
        end
      end
    end
  end
  end
end
