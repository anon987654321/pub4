# frozen_string_literal: true

require_relative "../../../operator/ruby_runner"

require "open3"
require "json"

module Master
  module Review
    module Scan
      module Laws
        # Shared plumbing for rules that bridge an external Ruby linter: locate the
        # binary and run it for a parsed JSON report. Mixed in rather than inherited
        # so the helper itself never lands in the auto-registering Rule registry.
        module ExternalLinter
          # Opt-in, and the reason is measured rather than argued. Default-on for one
          # afternoon let rubocop autocorrect inside the four-tree ladder, and rubocop
          # disagrees with this tree about trailing commas: its Style/TrailingComma*
          # default is no_comma, while TRAILING_COMMAS here flags a multi-line collection
          # that lacks one and add_trailing_commas puts it back. Twenty-one files were
          # rewritten in one pass, and the next pass would have rewritten them again.
          # Two style authorities that both autofix cannot share a tree, so this one
          # waits until its config is reconciled with the law.
          def linter_available?(name)
            return false unless ENV["MASTER_EXTERNAL_LINT"] == "1"

            ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? { |dir| File.executable?(File.join(dir, name)) } ||
              File.exist?(File.join(@root, "bin", name))
          end

          class ReportError < StandardError; end

          # An empty or malformed report is not the same as a clean lint run.
          # The rule's check boundary converts this error into a visible finding;
          # returning nil here would silently retire the linter and count as clean.
          def report_failure(name, message)
            error = ReportError.new("#{name}: #{message}")
            Master::Ground::Swallow.log(error, context: "linter_report #{name}", severity: :load_bearing)
            raise error
          end

          def linter_json(*argv)
            stdout, stderr, status = Master::Io::Exec.capture3(
              ::Operator::RubyRunner.bundle_cmd(root: @root), "exec", *argv, chdir: @root
            )
            if stdout.empty?
              exit_status = status.respond_to?(:exitstatus) ? status.exitstatus : nil
              error = ReportError.new(
                "#{argv.first}: empty JSON stdout (exit=#{exit_status || "signal"}, stderr=#{stderr.to_s.empty? ? "empty" : "present"})"
              )
              Master::Ground::Swallow.log(error, context: "linter_json #{argv.first}", severity: :load_bearing)
              raise error
            end

            JSON.parse(stdout)
          rescue JSON::ParserError => e
            Master::Ground::Swallow.log(e, context: "linter_json #{argv.first}", severity: :load_bearing)
            raise ReportError, "#{argv.first}: invalid JSON stdout (#{e.message.lines.first.to_s.strip})"
          end
        end

        class RubocopLaw < Law
          include ExternalLinter

          def self.auto_build? = false

          declare id: "rubocop", severity: :warning, tags: %i[STYLE LINT], description: "RuboCop style/lint violation"

          def initialize(root:)
            super()
            @root = root
          end

          def check(_code, path:)
            return [] unless path.end_with?(".rb") && linter_available?("rubocop")

            data = linter_json("rubocop", "--format", "json", "--no-color", path)
            files = data.is_a?(Hash) ? data["files"] : nil
            unless files.is_a?(Array) && !files.empty? &&
                   files.all? { |file| file.is_a?(Hash) && file["offenses"].is_a?(Array) }
              report_failure("rubocop", "invalid JSON report shape; expected files with offense arrays")
            end

            files.flat_map do |file|
              file["offenses"].map do |offense|
                finding(
                  line: offense.dig("location", "line") || 1,
                  message: "rubocop: #{offense["cop_name"]} — #{offense["message"]}"
                )
              end
            end
          rescue StandardError => e
            [finding(line: 1, message: "rubocop: scan error — #{e.message}")]
          end
        end

        class ReekLaw < Law
          include ExternalLinter

          def self.auto_build? = false

          declare id: "reek", severity: :warning, tags: %i[SMELL ONE_JOB], description: "Reek code smell detected"

          def initialize(root:)
            super()
            @root = root
          end

          def check(_code, path:)
            return [] unless path.end_with?(".rb") && linter_available?("reek")

            smells = linter_json("reek", "--format", "json", path)
            unless smells.is_a?(Array) &&
                   smells.all? { |smell| smell.is_a?(Hash) && (smell["lines"].nil? || smell["lines"].is_a?(Array)) }
              report_failure("reek", "invalid JSON report shape; expected an array of smell records")
            end

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
