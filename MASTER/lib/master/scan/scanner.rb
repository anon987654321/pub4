# frozen_string_literal: true

require "etc"

module Master
  module Scan
    class Scanner
      RULES_PATH   = File.join(Master::ROOT, "data", "rules.yml").freeze
      POOL_SIZE    = [Etc.nprocessors, 8].min

      def initialize(rules: nil, event_bus: nil)
        @rules = rules || []
        @bus   = event_bus
        @mutex = Mutex.new
      end

      def scan(path, depth: :standard)
        return Result.err("file not found: #{path}", category: :validation) unless File.exist?(path)

        code     = File.read(path, encoding: "UTF-8")
        active   = active_rules(depth)
        findings = active.flat_map { |rule| rule.check(code, path:) }

        @bus&.publish("scan:complete", path:, depth:, count: findings.size)
        Result.ok(findings)
      rescue StandardError => e
        @bus&.publish("scan:error", path:, error: e.message)
        Result.err("scan failed: #{e.message}", category: :unknown)
      end

      SCAN_GLOB = "**/*.{rb,rake,erb,html,htm,css,scss,js,ts,jsx,tsx,zsh,sh,yml,yaml,md}".freeze

      def scan_dir(dir, depth: :standard, glob: SCAN_GLOB, stream: false)
        paths     = Dir.glob(File.join(dir, glob)).sort
        results   = Array.new(paths.size)
        threads   = []
        semaphore = Mutex.new
        index     = 0

        POOL_SIZE.times do
          threads << Thread.new do
            loop do
              current_index = semaphore.synchronize { (index += 1) - 1 }
              break if current_index >= paths.size
              path = paths[current_index]
              begin
                file_result = scan(path, depth:)
                results[current_index] = [path, file_result]
                if stream && file_result.respond_to?(:ok?) && file_result.ok?
                  count = file_result.value!.size
                  $stdout.puts "scan: #{path.sub(dir, "").delete_prefix("/")} #{count > 0 ? "#{count} violation(s)" : "ok"}" if count > 0
                  $stdout.flush
                end
              rescue StandardError => e
                @bus&.publish("scanner:thread_error", path:, error: e.message)
                results[current_index] = [path, Result.err(e.message, category: :unknown)]
              end
            end
          end
        end

        threads.each(&:join)
        Result.ok(results)
      rescue StandardError => e
        Result.err("scan_dir: #{e.message}", category: :unknown)
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

      def depth_rules
        @depth_rules ||= begin
          data = Master.load_yaml(RULES_PATH)
          data["scan_depths"] || {}
        end
      rescue StandardError => _e
        @depth_rules = {}
      end

      def active_rules(depth)
        allowed = depth_rules[depth.to_s]
        return @rules if allowed.nil? || allowed == ["all"] || allowed == :all
        @rules.select { |r| allowed.include?(r.class.name.split("::").last) || allowed.include?(r.id) }
      end
    end
  end
end
