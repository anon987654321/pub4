# frozen_string_literal: true

require "open3"
require "json"

module Master
  module Review
    module Scan
      module Rules
        # Shared plumbing for rules that bridge an external Ruby linter: locate the
        # binary and run it for a parsed JSON report. Mixed in rather than inherited
        # so the helper itself never lands in the auto-registering Rule registry.
        module ExternalLinter
          # Gated behind MASTER_EXTERNAL_LINT so shelling out to rubocop/reek is opt-in;
          # then usable only when the binary is on PATH or vendored under the repo's bin/.
          def linter_available?(name)
            return false unless ENV["MASTER_EXTERNAL_LINT"] == "1"

            ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? { |dir| File.executable?(File.join(dir, name)) } ||
              File.exist?(File.join(@root, "bin", name))
          end

          # Returns parsed JSON, or nil on empty output or a parse error. nil
          # also means "this linter found nothing", so an unreadable payload
          # cannot go by unsaid.
          def linter_json(*argv)
            stdout, = Master::Io::Exec.capture3(Master::BUNDLE_BIN, "exec", *argv, chdir: @root)
            return if stdout.empty?
            JSON.parse(stdout)
          rescue JSON::ParserError => e
            Master::Ground::Swallow.log(e, context: "linter_json #{argv.first}", severity: :load_bearing)
            nil
          end
        end

        class RubocopRule < Rule
          include ExternalLinter

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

          def check(_code, path:)
            return [] unless path.end_with?(".rb") && linter_available?("rubocop")

            data = linter_json("rubocop", "--format", "json", "--no-color", path)
            return [] unless data

            offenses = data.dig("files", 0, "offenses") || []
            offenses.map do |o|
              finding(line: o.dig("location", "line") || 1, message: "rubocop: #{o["cop_name"]} — #{o["message"]}")
            end
          rescue StandardError => e
            [finding(line: 1, message: "rubocop: scan error — #{e.message}")]
          end
        end

        class ReekRule < Rule
          include ExternalLinter

          def self.auto_build? = false

          def initialize(root:)
            super()
            @id = "reek"
            @description = "Reek code smell detected"
            @severity = :warning
            @auto_fix = false
            @rule_tags = %i[SMELL ONE_JOB]
            @root = root
          end

          def check(_code, path:)
            return [] unless path.end_with?(".rb") && linter_available?("reek")

            smells = linter_json("reek", "--format", "json", path)
            return [] unless smells

            smells.flat_map do |smell|
              (smell["lines"] || [1]).map do |line|
                finding(line:, message: "reek: #{smell["smell_type"]} — #{smell["message"]}")
              end
            end
          rescue StandardError => e
            [finding(line: 1, message: "reek: scan error — #{e.message}")]
          end
        end
      end
    end
  end
end
