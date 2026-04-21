# frozen_string_literal: true

require "yaml"

module Master
  module Scan
    # Scanner — runs configured scan rules against Ruby source files.
    #
    # scan_dir parallelizes across files with a thread pool sized to CPU count.
    # Each file is independent; rules share no mutable state between files.
    class Scanner
      DEPTHS_PATH  = File.join(Master::ROOT, "data", "scan_depths.yml").freeze
      POOL_SIZE    = [Etc.nprocessors, 8].min  # cap at 8 to avoid overwhelming VPS

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

      # Parallel file scan — spawns up to POOL_SIZE threads, one per file.
      # Results preserve input order.
      def scan_dir(dir, depth: :standard, glob: "**/*.rb")
        paths   = Dir.glob(File.join(dir, glob)).sort
        results = Array.new(paths.size)
        threads = []
        semaphore = Mutex.new
        index = 0

        POOL_SIZE.times do
          threads << Thread.new do
            loop do
              i = semaphore.synchronize { idx = index; index += 1; idx }
              break if i >= paths.size
              results[i] = [paths[i], scan(paths[i], depth:)]
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
        @depth_rules ||= YAML.safe_load_file(DEPTHS_PATH, aliases: true)
      rescue StandardError
        @depth_rules = {}
      end

      def active_rules(depth)
        allowed = depth_rules[depth.to_s]
        return @rules if allowed.nil? || allowed == ["all"] || allowed == :all
        @rules.select { |r| allowed.include?(r.id) }
      end
    end
  end
end
