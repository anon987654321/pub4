# frozen_string_literal: true

require "digest"
require "etc"
require "fileutils"
require "open3"
require "prism"

module Master
  module Judge
    module Scan
      class Scanner
        POOL_SIZE = [Etc.nprocessors, 8].min.freeze
        SCAN_GLOB = "**/*.{rb,rake,erb,html,htm,css,scss,js,ts,jsx,tsx,zsh,sh,yml,yaml,md}".freeze
        RUBY_EXT = %w[.rb .rake .gemspec].freeze
        FORBIDDEN_DEPTHS = %i[quick standard shallow].freeze
        MTIME_STATE_PATH = ".master/scan_mtime.yml".freeze
        SCAN_SINCE_EXT = /\.(rb|erb|yml|js|css|sh|zsh)\z/i.freeze
        SEMANTIC_RULE_NAMES = %w[SemanticRule].freeze

        attr_reader :rules

        # Preconditions for #scan:
        # - path must exist and be readable
        # - depth must be :deep (quick/standard/shallow raise ArgumentError)
        def initialize(rules: nil, event_bus: nil, file_sleep_s: 0, root: nil)
          @rules = Array(rules)
          @bus = event_bus
          @mutex = Mutex.new
          @file_sleep_s = file_sleep_s.to_f
          @root = root || Master::ROOT
          @mtime_state = load_mtime_state
          @processor = FileProcessor.new(event_bus: @bus)
        end

        def scan(path, depth: :deep, rules: nil)
          validate_depth!(depth)
          return Result.err("file not found: #{path}", category: :validation,
                            context: { file: "judge/scan/scanner.rb", method: "scan", attempted: path }) unless File.exist?(path)
          code = @processor.read_file(path)
          return code if code.err?

          ast = @processor.parse_ruby(code.value!, path)
          rule_set = rules || active_rules(depth)
          findings = @processor.process(path, code: code.value!, ast:, rule_set:)
          touch_mtime(path)
          publish_scan_result(path, depth, findings)
          Result.ok(findings)
        rescue StandardError => e
          @bus&.publish("scan:error", path:, error: e.message)
          Result.err("scan failed: #{e.message}", category: :infrastructure)
        end

        def scan_dir(dir, depth: :deep, glob: SCAN_GLOB, stream: false)
          validate_depth!(depth)
          paths   = Dir.glob(File.join(dir, glob)).sort
          Result.ok(parallel_map(paths) { |path, idx| scan_one(dir:, path:, depth:, stream:, index: idx) })
        rescue StandardError => e
          Result.err("scan_dir: #{e.message}", category: :infrastructure)
        end

        def scan_since(ref = "HEAD~1", dir: ".", depth: :deep, stream: false)
          validate_depth!(depth)
          paths = changed_paths_since(ref, dir)
          paths.concat(master_lib_paths_since(ref)) unless File.expand_path(dir) == Master::ROOT
          paths = paths.uniq.select { |p| File.exist?(p) && p.match?(SCAN_SINCE_EXT) }
          Result.ok(parallel_map(paths) { |path, idx| scan_one(dir:, path:, depth:, stream:, index: idx) })
        rescue StandardError => e
          Result.err("scan_since: #{e.message}", category: :infrastructure)
        end

        def add_rule(rule)
          @rules << rule
          self
        end

        def set_agent(agent)
          @rules.each { |r| r.set_agent(agent) if r.respond_to?(:set_agent) }
          self
        end

        private

        def validate_depth!(depth)
          return unless FORBIDDEN_DEPTHS.include?(depth)

          raise ArgumentError, "forbidden scan depth #{depth.inspect} — deep only (DEEP_SCAN_ONLY)"
        end

        def read_file(path)
          code = File.read(path, encoding: "UTF-8")
          @bus&.publish("scan:file_read", path:, sha256: Digest::SHA256.hexdigest(code))
          Result.ok(code)
        end

        def parse_ruby(code, path)
          return unless RUBY_EXT.include?(File.extname(path))
          result = Prism.parse(code)
          result.success? ? result.value : nil
        rescue StandardError => e
          @bus&.publish("scan:parse_error", path:, error: e.message)
          nil
        end

        def apply_rules(code, ast, path, rule_set)
          fast_rules, semantic_rules = partition_rules(rule_set)
          findings = fast_rules.flat_map { |rule| run_rule(rule:, code:, ast:, path:) }
          return findings if semantic_rules.empty?
          return findings if findings.empty?

          findings + semantic_rules.flat_map { |rule| run_rule(rule:, code:, ast:, path:) }
        end

        def partition_rules(rule_set)
          semantic = []
          fast = rule_set.reject do |rule|
            name = rule.class.name&.split("::")&.last
            next false unless SEMANTIC_RULE_NAMES.include?(name)
            semantic << rule
            true
          end
          [fast, semantic]
        end

        def run_rule(rule:, code:, ast:, path:)
          if ast && rule.respond_to?(:check_ast)
            rule.check_ast(ast, code, path:)
          else
            rule.check(code, path:)
          end
        end

        def publish_scan_result(path, depth, findings)
          @bus&.publish("scan:complete", path:, depth:, count: findings.size)
        end

        def parallel_map(items)
          cursor  = Mutex.new
          index   = 0
          results = Array.new(items.size)
          threads = Array.new(POOL_SIZE) do
            Thread.new(results) do |thread_results|
              loop do
                i = cursor.synchronize { (index += 1) - 1 }
                break if i >= items.size
                thread_results[i] = yield(items[i], i)
              rescue StandardError => e
                @bus&.publish("scanner:thread_error", path: items[i], index: i, error: e.message)
                thread_results[i] = [items[i], Result.err(e.message, category: :infrastructure)]
              end
            end
          end
          threads.each(&:join)
          results
        end

        def scan_one(dir:, path:, depth:, stream:, index: nil)
          return [path, Result.ok([])] if unchanged_since_last_scan?(path)
          sleep @file_sleep_s if @file_sleep_s > 0
          file_result = scan(path, depth:)
          stream_progress(dir, path, file_result) if stream
          [path, file_result]
        rescue StandardError => e
          @bus&.publish("scanner:thread_error", path:, index:, error: e.message)
          [path, Result.err(e.message, category: :infrastructure)]
        end

        def stream_progress(dir, path, file_result)
          return unless file_result.ok?
          count = file_result.value!.size
          return unless count.positive?
          rel = path.sub(dir, "").delete_prefix("/")
          $stdout.puts "scan: #{rel} #{count} violation(s)"
          $stdout.flush
        end

        def depth_rules
          @depth_rules ||= begin
            data = Master.load_yaml(Master::RULES_PATH)
            data["scan_depths"] || {}
          end
        rescue StandardError => _e
          @depth_rules = {}
        end

        def active_rules(depth)
          allowed = depth_rules[depth.to_s]
          return @rules if allowed.nil? || allowed == ["all"] || allowed == :all
          @rules.select { |r|
            allowed.include?(r.class.name&.split("::")&.last) || allowed.include?(r.id)
          }
        end

        # Pure Ruby reader for data/rules.yml prediction_engine.
        # Gates autofix below per-rule confidence threshold.
        def prediction_thresholds
          @prediction_thresholds ||= (Master.load_yaml(Master::RULES_PATH)["prediction_engine"] || {})
        rescue StandardError
          {}
        end

        def should_autofix?(rule_id, observed_conf)
          t = prediction_thresholds[rule_id.to_s] || prediction_thresholds[rule_id]
          return true unless t && t["confidence"]
          observed_conf.to_f >= t["confidence"].to_f
        end

        def changed_paths_since(ref, dir)
          out, _, status = Open3.capture3("git", "-C", dir, "diff", "--name-only", "#{ref}...HEAD")
          return [] unless status.success?
          out.lines.map(&:strip).reject(&:empty?).map { |rel| File.join(dir, rel) }
        end

        def master_lib_paths_since(ref)
          lib_root = File.join(Master::ROOT, "lib")
          out, _, status = Open3.capture3("git", "-C", Master::ROOT, "diff", "--name-only", "#{ref}...HEAD")
          return [] unless status.success?
          out.lines.map(&:strip).reject(&:empty?)
             .select { |rel| rel.start_with?("lib/") }
             .map { |rel| File.join(Master::ROOT, rel) }
             .select { |p| File.exist?(p) && p.start_with?(lib_root) }
        end

        def unchanged_since_last_scan?(path)
          mtime = (File.mtime(path).to_i rescue nil)
          return false unless mtime
          @mutex.synchronize { @mtime_state[path] == mtime }
        end

        def touch_mtime(path)
          mtime = (File.mtime(path).to_i rescue nil)
          return unless mtime
          @mutex.synchronize do
            @mtime_state[path] = mtime
            persist_mtime_state!
          end
        end

        def load_mtime_state
          path = File.join(@root, MTIME_STATE_PATH)
          return {} unless File.exist?(path)
          Master.load_yaml(path) || {}
        rescue StandardError
          {}
        end

        def persist_mtime_state!
          path = File.join(@root, MTIME_STATE_PATH)
          FileUtils.mkdir_p(File.dirname(path))
          File.write(path, @mtime_state.to_yaml)
        rescue StandardError => e
          @bus&.publish("scanner:mtime_persist_error", error: e.message)
        end
      end
    end
  end
end
