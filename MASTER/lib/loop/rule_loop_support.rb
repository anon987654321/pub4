# frozen_string_literal: true

require "digest"

module Master
  module Loop
    # Policy and bookkeeping helpers shared by RuleLoop's fix strategies.
    module RuleLoopSupport
      private

      def convergence_cfg
        @convergence_cfg ||= Master.load_yaml(Master::RULES_PATH).dig("thresholds", "convergence") || {}
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "rule_loop.convergence_cfg", event_bus: @bus)
        {}
      end

      def genetic_autofix_candidates
        convergence_cfg["genetic_autofix_candidates"] || RuleLoop::GENETIC_AUTOFIX_CANDIDATES
      end

      def scan_all(path)
        result = @scanner.scan(path)
        result.ok? ? result.value! : []
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "rule_loop.scan_all", event_bus: @bus, path:)
        []
      end

      def autofix_allowed?(violation)
        return true unless @scanner.respond_to?(:should_autofix?, true)

        confidence = violation[:confidence] || violation["confidence"] || 1.0
        allowed = @scanner.__send__(:should_autofix?, violation[:rule], confidence)
        @bus&.publish("rule_loop:autofix_skipped", rule: violation[:rule], confidence:) unless allowed
        allowed
      end

      def fingerprint_matches?(violation)
        stored = violation[:fingerprint] || violation["fingerprint"]
        return true if stored.to_s.empty?
        return false unless File.file?(violation[:file].to_s)

        current = semantic_fingerprint_for(violation[:file].to_s)
        return true if current == stored.to_s

        @bus&.publish(
          "rule_loop:stale_scan", rule: @rule.id, file: violation[:file], expected: stored, actual: current
        )
        false
      end

      def note_unverified_fix(violation)
        return if test_file_for(violation[:file]).any?

        @bus&.publish(
          "rule_loop:fix_unverified", rule: @rule.id, file: violation[:file], note: "fix unverified — add test"
        )
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "rule_loop.note_unverified_fix", event_bus: @bus)
        nil
      end

      def semantic_fingerprint_for(path)
        src = File.read(path, encoding: "UTF-8")
        counts = {
          line_count: src.lines.count,
          class_count: src.scan(/^\s*class\s+/).size,
          method_count: src.scan(/^\s*def\s+/).size,
          def_names: src.scan(/^\s*def\s+([a-zA-Z_][\w!?=]*)/).flatten.sort,
          constant_names: src.scan(/\b([A-Z][A-Z0-9_]*(?:::[A-Z][A-Z0-9_]*)*)\b/).flatten.sort,
        }
        Digest::SHA256.hexdigest(Marshal.dump(counts))
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "rule_loop.semantic_fingerprint", event_bus: @bus, path:)
        ""
      end

      def test_file_for(path)
        rel = path.to_s.delete_prefix("#{@root}/")
        stem = File.basename(rel, File.extname(rel))
        patterns = [
          File.join(@root, "test", "**", "*#{stem}*.rb"),
          File.join(@root, "MASTER", "test", "**", "*#{stem}*.rb"),
        ]
        patterns.flat_map { |pattern| Dir.glob(pattern) }.uniq.select { |file| File.file?(file) }
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "rule_loop.test_file_for", event_bus: @bus, path:)
        []
      end

      def handle_fix_exception(error, violation, event:)
        message = error.message.to_s
        info = (@failure_taxonomy || Ground::FailureTaxonomy.new).handle(error)
        publish_fix_failure(info[:category], event, violation, message)
        info[:category] == :transient ? :retry : :stop
      end

      def publish_fix_failure(category, event, violation, message)
        name = {
          permanent: "rule_loop:fail_fast",
          ambiguous: "rule_loop:human_intervention",
        }.fetch(category, event)
        @bus&.publish(name, rule: violation[:rule], file: violation[:file], error: message[0, 120])
      end

      def record_outcomes(files, outcome)
        return unless @learnings

        extensions = files.filter_map { |file| File.extname(file).downcase.delete(".").presence }
        ext = extensions.tally.max_by { |_, count| count }&.first || "unknown"
        @learnings.record(rule: @rule.id, file_type: ext, outcome:)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "rule_loop.record_outcomes", event_bus: @bus, rule: @rule.id)
      end
    end
  end
end
