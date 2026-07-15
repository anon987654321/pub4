# frozen_string_literal: true

module Master
  module Loop
    class RuleLoop
      # Staleness/verification checks run before and after we apply a fix
      # (fingerprint drift, missing test coverage) — separate from RuleLoop's
      # own scan/prompt/apply pipeline.
      module FixVerification
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
      end
    end
  end
end
