# frozen_string_literal: true

require "etc"
require "open3"
require "timeout"
require_relative "cross_file_analysis"
require_relative "file_processor"
require_relative "engines/path_filter"
require_relative "engines/progress_reporter"
require_relative "engines/transport"
require_relative "mechanical_autofix"

module Master
  module Review
    module Scan
      class Scanner
        include ProgressReporter
        include Transport

        # The Scanner is the coordinator of the review process. What it walks
        # is PathFilter's decision, how it walks is Transport's, and what it
        # says while walking is ProgressReporter's; rule application is its own.

        SCAN_GLOB = "**/*.{rb,rake,erb,html,htm,css,scss,js,ts,jsx,tsx,zsh,sh,yml,yaml,json,md}".freeze
        REQUIRED_DEPTH = :deep
        MAX_VIOLATION_OBJECTS = 100_000

        attr_reader :rules

        def self.skip_path?(path, root: nil)
          PathFilter.skip_path?(path, root:)
        end

        def initialize(rules: [], event_bus: nil, file_sleep_s: 0)
          @rules = Array(rules)
          @bus = event_bus
          @mutex = Mutex.new
          @file_sleep_s = file_sleep_s.to_f
          @file_processor = FileProcessor.new(event_bus: @bus)
          @stream_autofixes = []
        end

        attr_reader :stream_autofixes

        def scan(path, depth: :deep, rules: nil)
          validate_depth!(depth)
          @file_processor.call(path:, depth:, rules: rules || active_rules(depth))
        end

        def scan_dir(dir, depth: :deep, glob: SCAN_GLOB, stream: false, autofix: false, autofix_root: nil, rules: nil)
          validate_depth!(depth)
          paths = Dir.glob(File.join(dir, glob)).select { |path| scannable_path?(path, dir) }
          reset_scan_progress(paths.size) if stream
          pairs = parallel_map(paths) { |path, idx|
            scan_one(dir:, path:, depth:, stream:, index: idx, autofix:, autofix_root:, rules:)
          }
          pairs.concat(cross_file_pairs(dir, paths))
          Result.ok(prune_violation_objects(pairs))
        rescue StandardError => e
          Result.err("scan_dir: #{e.message}", category: :infrastructure)
        end

        def scan_since(ref = "HEAD~1", dir: ".", depth: :deep, stream: false)
          validate_depth!(depth)
          repo_root = git_toplevel(dir)
          return Result.err("git root failed", category: :validation) unless repo_root

          changed = changed_since(ref, repo_root)
          return changed if changed.err?

          paths = scan_since_paths(changed.value!, dir:, repo_root:)
          pairs = parallel_map(paths) { |path, idx| scan_one(dir:, path:, depth:, stream:, index: idx) }
          Result.ok(prune_violation_objects(pairs))
        rescue StandardError => e
          Result.err("scan_since: #{e.message}", category: :infrastructure)
        end

        def add_rule(rule)
          @rules << rule
          self
        end

        # Flat findings with :path merged in. scan_dir returns Result wrapping
        # [path, Result] pairs whose inner values are hashes, so f.rule raises
        # and the path is discarded unless the caller knows the unwrap. This is
        # the one documented way to get them out.
        def findings(paths, depth: :deep)
          Array(paths).flat_map { |path| findings_for(path, depth:) }
        end

        def set_agent(agent)
          @rules.each { |r| r.set_agent(agent) if r.respond_to?(:set_agent) }
          self
        end

        def skip_semantic!
          @file_processor.skip_semantic! if @file_processor.respond_to?(:skip_semantic!)
        end

        private

        def findings_for(path, depth:)
          if File.directory?(path)
            result = scan_dir(path, depth:)
            return [] unless result.respond_to?(:ok?) && result.ok?

            result.value!.flat_map do |file, res|
              rows = res.respond_to?(:ok?) && res.ok? ? res.value! : []
              rows.map { |item| item.merge(path: file) }
            end
          else
            result = scan(path, depth:)
            rows = result.respond_to?(:ok?) && result.ok? ? result.value! : []
            rows.map { |item| item.merge(path:) }
          end
        end

        def scannable_path?(path, root)
          File.file?(path) && !self.class.skip_path?(path, root:)
        end

        def validate_depth!(depth)
          return if depth == REQUIRED_DEPTH
          raise ArgumentError, "forbidden scan depth #{depth.inspect} — deep only (DEEP_SCAN_ONLY)"
        end

        def git_toplevel(dir)
          out, _, status = git_capture("git", "-C", dir, "rev-parse", "--show-toplevel")
          status.success? ? out.strip : nil
        end

        def scan_one(dir:, path:, depth:, stream:, index: nil, autofix: false, autofix_root: nil, rules: nil)
          sleep @file_sleep_s if @file_sleep_s > 0
          file_result = scan(path, depth:, rules:)
          applied = autofix ? autofix_one(path, file_result, root: autofix_root || dir) : []
          if applied.any?
            file_result = scan(path, depth:, rules:)
            emit_autofixed(dir:, path:, applied:) if stream
          end
          emit_scan_progress(dir:, path:, file_result:) if stream
          [path, file_result]
        rescue StandardError => e
          @bus&.publish("scanner:thread_error", path:, index:, error: e.message)
          [path, Result.err(e.message, category: :infrastructure)]
        end

        def autofix_one(path, file_result, root:)
          applied = MechanicalAutofix.new(scanner: self, root:, event_bus: @bus).apply([[path, file_result]])
          return [] if applied.empty?

          @mutex.synchronize { @stream_autofixes.concat(applied) }
          applied
        end

        def emit_autofixed(dir:, path:, applied:)
          rel = path.sub(dir, "").delete_prefix("/")
          transforms = applied.flat_map { |row| Array(row.transforms) }.uniq.first(8).join(" ")
          unit = @scan_progress&.dig(:unit) || @through_scan_unit || "scan0"
          Master::Trace::Dmesg.status(unit, "autofixed #{rel} #{transforms}")
        end

        def cross_file_pairs(dir, paths)
          CrossFileAnalysis.new(root: dir).call(paths)
        rescue StandardError => e
          @bus&.publish("scanner:cross_file_error", path: dir, error: e.message)
          []
        end

        def prune_violation_objects(pairs)
          total = pairs.sum { |_path, result| Result.wrap(result).value_or([]).size }
          return pairs if total <= MAX_VIOLATION_OBJECTS

          remaining = MAX_VIOLATION_OBJECTS
          pruned = total - MAX_VIOLATION_OBJECTS
          pairs.reverse_each do |_path, result|
            findings = Result.wrap(result).value_or([])
            keep = [findings.size, remaining].min
            remaining -= keep
            findings.replace(findings.last(keep))
          end
          @bus&.publish("scanner:violations_pruned", pruned:, kept: MAX_VIOLATION_OBJECTS)
          pairs
        end

        def active_rules(_depth)
          @rules
        end

        def prediction_thresholds
          @prediction_thresholds ||= (Master.load_yaml(Master::RULES_PATH)["prediction_engine"] || {})
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "Scanner.prediction_thresholds")
          {}
        end

        def should_autofix?(rule_id, observed_conf)
          t = prediction_thresholds[rule_id.to_s] || prediction_thresholds[rule_id]
          return true unless t && t["confidence"]
          observed_conf.to_f >= t["confidence"].to_f
        end
      end
    end
  end
end
