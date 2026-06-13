# frozen_string_literal: true

require "digest"
require "etc"
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

        attr_reader :rules

        def initialize(rules: nil, event_bus: nil, file_sleep_s: 0)
          @rules = Array(rules)
          @bus = event_bus
          @mutex = Mutex.new
          @file_sleep_s = file_sleep_s.to_f
        end

        def scan(path, depth: :deep, rules: nil)
          validate_depth!(depth)
          code = read_file(path)
          return code if code.err?

          ast = parse_ruby(code.value!, path)
          findings = apply_rules(code.value!, ast, path, rules || active_rules(depth))
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
          out, _, status = Open3.capture3("git", "-C", dir, "diff", "--name-only", "#{ref}...HEAD")
          return Result.err("git diff failed", category: :validation) unless status.success?
                    .map { |rel| File.join(dir, rel) }
                    .select { |p| File.exist?(p) && File.extname(p).match?(/\.(rb|erb|yml|js|css|sh|zsh)\z/) }
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

        def read_file(path)
          return Result.err("file not found: #{path}", category: :validation) unless File.exist?(path)

          code = File.read(path, encoding: "UTF-8")
          @bus&.publish("scan:file_read", path:, sha256: Digest::SHA256.hexdigest(code))
          Result.ok(code)
        end

        def parse_ruby(code, path)
          return unless RUBY_EXT.include?(File.extname(path))
          result.success? ? result.value : nil
        rescue StandardError => e
          @bus&.publish("scan:parse_error", path:, error: e.message)
          nil
        end

        def apply_rules(code, ast, path, rule_set)
          rule_set.flat_map { |rule| run_rule(rule:, code:, ast:, path:) }
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
          return unless count.positive?
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
            allowed.include?(r.class.name&.split("::")&.last) || allowed.include?(r.id),
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
        end

        # HALLUCINATION rule: lexical/semantic detector for claim_without_reading; deferred pending council wiring.
      end
    end
  end
end
