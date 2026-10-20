# frozen_string_literal: true

require_relative "../../../operator/ruby_runner"

require "digest"
require "fileutils"
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
            return false if ENV["MASTER_EXTERNAL_LINT"] == "0"

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

          # Files that change a linter's verdict besides the file it reads.
          LINT_INPUTS = %w[.rubocop.yml .reek.yml config.reek Gemfile.lock].freeze

          # A report is a function of the argv, the file and the linter's configuration, so it is kept by the
          # digest of all three: a gate over 1800 unchanged files spent its whole budget spawning rubocop and
          # reek once each and never finished.
          def linter_json(*argv)
            key = lint_cache_key(argv)
            cached = key && read_lint_cache(key)
            return cached if cached

            report = run_linter_json(*argv)
            write_lint_cache(key, report) if key
            report
          end

          def lint_cache_key(argv)
            target = File.expand_path(argv.last.to_s, @root)
            return unless File.file?(target)

            inputs = LINT_INPUTS.map { |name| File.join(@root, name) }.select { |path| File.file?(path) }
            parts = [argv.first(argv.size - 1), target, Digest::SHA256.file(target).hexdigest,
                     inputs.map { |path| Digest::SHA256.file(path).hexdigest }]
            Digest::SHA256.hexdigest(JSON.generate(parts))
          end

          def lint_cache_path(key) = File.join(@root, ".master", "lint_cache", "#{key}.json")

          def read_lint_cache(key)
            path = lint_cache_path(key)
            JSON.parse(File.read(path)) if File.file?(path)
          rescue JSON::ParserError, SystemCallError => e
            Master::Ground::Swallow.log(e, context: "lint_cache read")
            nil
          end

          def write_lint_cache(key, report)
            path = lint_cache_path(key)
            FileUtils.mkdir_p(File.dirname(path))
            File.write("#{path}.tmp#{Process.pid}", JSON.generate(report))
            File.rename("#{path}.tmp#{Process.pid}", path)
          rescue SystemCallError => e
            Master::Ground::Swallow.log(e, context: "lint_cache write")
          end

          def run_linter_json(*argv)
            stdout, stderr, status = Master::Io::Exec.capture3(
              ::Operator::RubyRunner.bundle_cmd(root: @root), "exec", *argv, chdir: @root
            )
            raise empty_report_error(argv.first, stderr:, status:) if stdout.empty?

            JSON.parse(stdout)
          rescue JSON::ParserError => e
            Master::Ground::Swallow.log(e, context: "linter_json #{argv.first}", severity: :load_bearing)
            raise ReportError, "#{argv.first}: invalid JSON stdout (#{e.message.lines.first.to_s.strip})"
          end

          def empty_report_error(name, stderr:, status:)
            first = stderr.to_s.lines.map(&:strip).find { |line| !line.empty? }.to_s[0, 160]
            detail = "exit=#{status.exitstatus || "signal"}, stderr=#{first.empty? ? "empty" : first}"
            error = ReportError.new("#{name}: empty JSON stdout (#{detail})")
            Master::Ground::Swallow.log(error, context: "linter_json #{name}", severity: :load_bearing)
            error
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

            # Only MASTER carries a .rubocop.yml, so a file in another tree would be judged by rubocop's
            # defaults, which prefer single quotes where the house style is double.
            config = File.join(@root, ".rubocop.yml")
            data = linter_json("rubocop", "--config", config, "--format", "json", "--no-color", path)
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
                   smells.all? do |smell|
                     smell.is_a?(Hash) &&
                       smell["smell_type"].is_a?(String) && !smell["smell_type"].empty? &&
                       smell["message"].is_a?(String) && !smell["message"].empty? &&
                       (smell["lines"].nil? ||
                         (smell["lines"].is_a?(Array) &&
                           smell["lines"].all? { |line| line.is_a?(Integer) && line.positive? }))
                   end
              report_failure("reek", "invalid JSON report shape; expected smell_type, message and positive line numbers")
            end

            smells.flat_map do |smell|
              lines = Array(smell["lines"])
              lines = [1] if lines.empty?
              lines.map do |line|
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
