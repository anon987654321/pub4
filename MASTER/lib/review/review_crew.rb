# frozen_string_literal: true

require "json"
require "set"
require "thread"
require_relative "review_crew/agents"

module Master
  module Review
    class ReviewCrew
      def initialize(agent:, event_bus: nil, root:, code_index: nil, reference_graph: nil)
        @agent = agent
        @bus = event_bus
        @root = root
        @code_index = code_index
        @reference_graph = reference_graph
      end

      def run(target:)
        files = target_files(target)
        return Result.err("review_crew: no files under #{target}") if files.empty?

        collected = dispatch_workers(build_workers, files)
        synthesized = synthesize(collected, target:, files:)
        Result.ok({ summary: synthesized, agents: collected })
      rescue StandardError => e
        Result.err("review_crew: #{e.message}", category: :infrastructure)
      end

      private

      def build_workers
        [
          SecurityAgent.new,
          PerformanceAgent.new,
          StyleAgent.new,
          ArchitectureAgent.new(root: @root, code_index: @code_index, reference_graph: @reference_graph),
          MinimalistAgent.new,
          ChaosAgent.new,
        ]
      end

      def dispatch_workers(workers, files)
        queue = Queue.new
        workers.each { |worker| Thread.new { run_worker(worker, files, queue) } }

        collected = []
        workers.size.times { collected << queue.pop }
        collected
      end

      def run_worker(worker, files, queue)
        started = Time.now
        @bus&.publish("review_crew:agent_started", agent: worker.name, files: files.size)
        files.each do |file|
          code = File.read(file, encoding: "UTF-8") rescue next
          worker.analyze(code, file)
        end
        # BaseAgent#analyze accumulates into worker.findings and returns the whole
        # growing array; read it once here instead of concatenating per file
        # (which duplicated earlier files' findings quadratically).
        worker_findings = worker.findings
        elapsed = Time.now - started
        @bus&.publish("review_crew:agent_done", agent: worker.name, findings: worker_findings.size, elapsed:)
        queue << { agent: worker.name, findings: worker_findings.map(&:to_h), elapsed: }
      rescue StandardError => e
        @bus&.publish("review_crew:agent_error", agent: worker.name, error: e.message)
        queue << { agent: worker.name, findings: [], elapsed: 0.0, error: e.message }
      end

      def target_files(target)
        abs = File.expand_path(target, @root)
        return [abs] if File.file?(abs)

        Dir.glob(File.join(abs, "**/*.{rb,rake,erb,html,htm,css,scss,js,ts,yml,yaml,md}"))
           .select { |file| File.file?(file) }
      end

      def synthesize(collected, target:, files:)
        prompt = <<~PROMPT
          Consolidate the following review findings into one concise review summary.
          Keep the summary actionable and mention the highest-risk issue first.

          Target: #{target}

          Findings JSON:
          #{JSON.pretty_generate(collected)}
        PROMPT

        text = @agent.ask_once(prompt)
        summary = text.to_s.strip
        deep = deep_security_audit(collected, files)
        [summary, deep].reject(&:empty?).join("\n\n")
      rescue StandardError
        [local_summary(collected, target), deep_security_audit(collected, files)].reject(&:empty?).join("\n\n")
      end

      def deep_security_audit(collected, files)
        security_findings = collected.flat_map { |entry| Array(entry[:findings]) }.select do |finding|
          finding[:agent].to_s == "SecurityAgent" || finding["agent"].to_s == "SecurityAgent"
        end
        trigger = files.any? do |file|
          file.to_s.match?(%r{/(auth|session|user|admin|payment|credential)}i)
        end || security_findings.any? { |finding| finding[:severity].to_s == "error" }
        return "" unless trigger

        prompt = <<~PROMPT
          Perform an OWASP Top 10 style security audit on these findings.
          Return a concise paragraph and call out the most urgent issue.

          Findings JSON:
          #{JSON.pretty_generate(security_findings)}
        PROMPT

        @agent.ask_once(prompt)
      rescue StandardError
        ""
      end

      def local_summary(collected, target)
        total = collected.sum { |entry| Array(entry[:findings]).size }
        top = collected.flat_map { |entry| Array(entry[:findings]) }
        grouped = top.group_by { |finding| finding[:category] || finding["category"] }
        lines = ["review_crew: #{target} — #{total} finding(s)"]
        grouped.sort_by { |category, findings| [-findings.size, category.to_s] }.each do |category, findings|
          lines << "  #{category}: #{findings.size}"
        end
        top.first(8).each do |finding|
          lines << "  - #{finding[:agent]} L#{finding[:line]} #{finding[:message]} -> #{finding[:suggestion]}"
        end
        lines.join("\n")
      end
    end
  end
end
