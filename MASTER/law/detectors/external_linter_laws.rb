# frozen_string_literal: true

require_relative "../../lib/operator/ruby_runner"
require_relative "../../lib/ground/library_verify"
require_relative "../../lib/fix/scan/source_override"

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
          PREFETCH_BATCH = 200

          # One linter process over many uncached files, its report split into the entries a run on each
          # file alone would have kept. A scan of 4,900 files started rubocop and reek once per file, about
          # three seconds each and nearly all of it boot, so a cold cache took hours to fill. A batch that
          # fails leaves its files to the single-file run, as before.
          def prefetch(paths)
            return unless linter_available?(linter_name)

            todo = paths.select { |path| path.end_with?(".rb") && File.file?(path) }
            todo = todo.reject { |path| (key = lint_cache_key(single_argv(path))) && read_lint_cache(key) }
            todo.each_slice(PREFETCH_BATCH) { |batch| prefetch_batch(batch) }
          end

          def prefetch_batch(batch)
            report = run_linter_json(*single_argv(batch.first)[0...-1], *batch)
            batch.each do |path|
              key = lint_cache_key(single_argv(path))
              write_lint_cache(key, report_for(report, path)) if key
            end
          rescue StandardError => e
            Master::Ground::Swallow.log(e, context: "linter prefetch #{linter_name}")
          end

          def same_file?(reported, path) = File.expand_path(reported.to_s, @root) == File.expand_path(path, @root)

          # A report is a function of the argv, the file and the linter's configuration, so it is kept by the
          # digest of all three: a check over 1800 unchanged files spent its whole budget spawning rubocop and
          # reek once each and never finished.
          def linter_json(*argv)
            key = lint_cache_key(argv)
            cached = key && read_lint_cache(key)
            return cached if cached

            report = run_linter_json(*argv)
            write_lint_cache(key, report) if key
            report
          end

          # The report for +path+ as the scan reads it. A path with a Fix::Scan::SourceOverride (the
          # staged blob a pre-commit lint judges) is piped to the linter under its real name, so its
          # config and excludes apply and the working tree's other version is never read.
          def report_for_path(path)
            source = Master::Fix::Scan::SourceOverride.for(path)
            return linter_json(*single_argv(path)) unless source

            argv = stdin_argv(path)
            key = lint_cache_key(argv, source:)
            cached = key && read_lint_cache(key)
            return cached if cached

            report = run_linter_json(*argv, stdin_data: source)
            write_lint_cache(key, report) if key
            report
          end

          def lint_cache_key(argv, source: nil)
            target = File.expand_path(argv.last.to_s, @root)
            digest = read_digest(target, source)
            return unless digest

            inputs = LINT_INPUTS.map { |name| File.join(@root, name) }.select { |path| File.file?(path) }
            parts = [argv.first(argv.size - 1), target, digest,
                     inputs.map { |path| input_digest(path) }]
            Digest::SHA256.hexdigest(JSON.generate(parts))
          end

          # The digest of what the linter reads: the piped source, else the file; nil with neither.
          def read_digest(target, source)
            return Digest::SHA256.hexdigest(source) if source

            Digest::SHA256.file(target).hexdigest if File.file?(target)
          end

          # The lock by the versions it pins; its constraint lines flip between bundlers with no change.
          def input_digest(path)
            return Master::Ground::LibraryVerify.pinned_digest(path) if File.basename(path) == "Gemfile.lock"

            Digest::SHA256.file(path).hexdigest
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

          def run_linter_json(*argv, stdin_data: nil)
            stdout, stderr, status = Master::Io::Exec.capture3(
              ::Operator::RubyRunner.bundle_cmd(root: @root), "exec", *argv, chdir: @root, stdin_data:
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

        class RubocopLaw < Detector
          include ExternalLinter


          def initialize(root:)
            super()
            @root = root
          end

          def check(_code, path:)
            return [] unless path.end_with?(".rb") && linter_available?("rubocop")

            # Only MASTER carries a .rubocop.yml, so a file in another tree would be judged by rubocop's
            # defaults, which prefer single quotes where the house style is double.
            # A root without one, the repository root /fix probes from, is judged by MASTER's as well.
            data = report_for_path(path)
            files = data.is_a?(Hash) ? data["files"] : nil
            unless files.is_a?(Array) && !files.empty? &&
                   files.all? { |file| file.is_a?(Hash) && file["offenses"].is_a?(Array) }
              report_failure("rubocop", "invalid JSON report shape; expected files with offense arrays")
            end

            files.flat_map do |file|
              file["offenses"].map do |offense|
                finding(
                  line: offense.dig("location", "line") || 1,
                  message: "rubocop: #{offense["cop_name"]} — #{offense["message"]}",
                )
              end
            end
          rescue StandardError => e
            [finding(line: 1, message: "rubocop: scan error — #{e.message}")]
          end

          def linter_name = "rubocop"

          def single_argv(path)
            config = File.join(@root, ".rubocop.yml")
            config = File.join(Master::ROOT, ".rubocop.yml") unless File.file?(config)
            ["rubocop", "--config", config, "--format", "json", "--no-color", path]
          end

          def stdin_argv(path) = [*single_argv(path)[0...-1], "--stdin", path]

          # The batch report narrowed to one file, as rubocop would have answered for that file alone.
          def report_for(report, path)
            entry = Array(report["files"]).find { |file| same_file?(file["path"], path) }
            report.merge("files" => [entry || { "path" => path, "offenses" => [] }])
          end
        end

        ::Law.define(:rubocop) do
          detector RubocopLaw
          tags %i[STYLE LINT]
          fix "RuboCop style/lint violation"
          proved_by "test/test_external_linter_laws.rb"
        end

        class ReekLaw < Detector
          include ExternalLinter


          def initialize(root:)
            super()
            @root = root
          end

          def check(_code, path:)
            return [] unless path.end_with?(".rb") && linter_available?("reek")

            smells = report_for_path(path)
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

          def linter_name = "reek"

          def single_argv(path) = ["reek", "--format", "json", path]

          def stdin_argv(path) = ["reek", "--format", "json", "--stdin-filename", path]

          # The smells the batch found in this file; a file with none answers an empty list.
          def report_for(report, path) = Array(report).select { |smell| same_file?(smell["source"], path) }
        end

        ::Law.define(:reek) do
          detector ReekLaw
          tags %i[SMELL ONE_JOB]
          fix "Reek code smell detected"
          proved_by "test/test_external_linter_laws.rb"
        end
      end
    end
  end
end
