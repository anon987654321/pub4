# frozen_string_literal: true

module Master
  module Fix
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

        # The file's own test, run once the fix is on disk. The rescan proves the
        # rule stopped firing; only the test proves the behaviour survived it.
        # Named exactly, test_<stem>.rb, because test_file_for's loose match finds
        # every test sharing a common stem. nil means the test passed or there
        # is none; a string names the failure.
        def failing_test_for(path)
          test = own_test_for(path)
          return unless test

          out, status = Master::Io::Exec.capture2e(RbConfig.ruby, test, chdir: File.dirname(File.dirname(test)))
          status.success? ? nil : "#{File.basename(test)}: #{out.lines.last(3).join.strip}"
        end

        def own_test_for(path)
          name = "test_#{File.basename(path.to_s, File.extname(path.to_s))}.rb"
          test_file_for(path).find { |file| File.basename(file) == name }
        end

        # Delegates rather than computes: Review::Scan::SemanticFingerprint.for
        # stamps the fingerprint this compares against, and two copies of one
        # formula disagree the moment either gains a field. That module's own
        # comment holds what the disagreement cost.
        def semantic_fingerprint_for(path)
          src = File.read(path, encoding: "UTF-8")
          Master::Review::Scan::SemanticFingerprint.for(src)
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
          raise "rule_loop: test discovery failed for #{path}: #{e.class}: #{e.message}"
        end
        end
      end
    end
  end
end
