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

      def initialize(rules: nil, event_bus: nil, file_sleep_s: 0)
        @rules = Array(rules)
        @bus = event_bus
        @mutex = Mutex.new
        @file_sleep_s = file_sleep_s.to_f
      end

      def scan(path, depth: :deep, rules: nil)
        raise ArgumentError, "forbidden scan depth #{depth.inspect} — deep only (DEEP_SCAN_ONLY)" if FORBIDDEN_DEPTHS.include?(depth)
        return Result.err("file not found: #{path}", category: :validation) unless File.exist?(path)

        code = File.read(path, encoding: "UTF-8")
        @bus&.publish("scan:file_read", path:, sha256: Digest::SHA256.hexdigest(code))
        ast = parse_ruby(code, path)
        rule_set = rules || active_rules(depth)
        findings = rule_set.flat_map { |rule| run_rule(rule:, code:, ast:, path:) }
        @bus&.publish("scan:complete", path:, depth:, count: findings.size)
        Result.ok(findings)
      rescue StandardError => e
        @bus&.publish("scan:error", path:, error: e.message)
        Result.err("scan failed: #{e.message}", category: :infrastructure)
      end

      def scan_dir(dir, depth: :deep, glob: SCAN_GLOB, stream: false)
        raise ArgumentError, "forbidden scan depth #{depth.inspect} — deep only (DEEP_SCAN_ONLY)" if FORBIDDEN_DEPTHS.include?(depth)
        paths   = Dir.glob(File.join(dir, glob)).sort
        results = Array.new(paths.size)
        parallel_each(paths) { |path, idx| results[idx] = scan_one(dir:, path:, depth:, stream:) }
        Result.ok(results)
      rescue StandardError => e
        Result.err("scan_dir: #{e.message}", category: :infrastructure)
      end

      def scan_since(ref = "HEAD~1", dir: ".", depth: :deep, stream: false)
        raise ArgumentError, "forbidden scan depth #{depth.inspect} — deep only (DEEP_SCAN_ONLY)" if FORBIDDEN_DEPTHS.include?(depth)
        out, _, status = Open3.capture3("git", "-C", dir, "diff", "--name-only", "#{ref}...HEAD")
        return Result.err("git diff failed", category: :validation) unless status.success?
        paths = out.lines.map(&:strip).reject(&:empty?)
                  .map { |rel| File.join(dir, rel) }
                  .select { |p| File.exist?(p) && File.extname(p).match?(/\.(rb|erb|yml|js|css|sh|zsh)\z/) }
        results = Array.new(paths.size)
        parallel_each(paths) { |path, idx| results[idx] = scan_one(dir:, path:, depth:, stream:) }
        Result.ok(results)
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

      def parse_ruby(code, path)
        return unless RUBY_EXT.include?(File.extname(path))
        result = Prism.parse(code)
        result.success? ? result.value : nil
      rescue StandardError => e
        @bus&.publish("scan:parse_error", path:, error: e.message)
        nil
      end

      def run_rule(rule:, code:, ast:, path:)
        if ast && rule.respond_to?(:check_ast)
          rule.check_ast(ast, code, path:)
        else
          rule.check(code, path:)
        end
      end

      def parallel_each(items)
        cursor  = Mutex.new
        index   = 0
        threads = Array.new(POOL_SIZE) do
          Thread.new do
            loop do
              i = cursor.synchronize { (index += 1) - 1 }
              break if i >= items.size
              yield items[i], i
            end
          end
        end
        threads.each(&:join)
      end

      def scan_one(dir:, path:, depth:, stream:)
        sleep @file_sleep_s if @file_sleep_s > 0
        file_result = scan(path, depth:)
        stream_progress(dir, path, file_result) if stream
        [path, file_result]
      rescue StandardError => e
        @bus&.publish("scanner:thread_error", path:, error: e.message)
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
    end
  end
  end
end
