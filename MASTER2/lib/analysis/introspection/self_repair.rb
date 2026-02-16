# frozen_string_literal: true

module MASTER
  module Analysis
    class Introspection
      class << self
        # Full repair pipeline with audit -> confirm -> fix -> test -> learn
        # @param files [String, Array<String>] File(s) to repair
        # @param dry_run [Boolean] Preview changes without writing
        # @param auto_confirm [Boolean] Skip confirmation gates
        # @return [Result] Ok with repair summary or Err
        def repair(files, dry_run: true, auto_confirm: false)
          files = [files] unless files.is_a?(Array)

          repaired = 0
          failed = 0
          skipped = 0

          # Step 1: Audit scan
          audit_result = if defined?(Audit)
            Audit.scan(files)
          else
            return Result.err("Audit module not available.")
          end

          return audit_result unless audit_result.ok?

          report = audit_result.value[:report]
          findings = report.prioritized

          UI.dim("  Found #{findings.size} issues") if defined?(UI)

          # Step 2: Process each finding
          findings.each do |finding|
            # Skip if dry_run
            if dry_run
              UI.dim("  [DRY RUN] Would repair: #{finding.message}") if defined?(UI)
              skipped += 1
              next
            end

            # Step 3: Confirmation gate (unless auto_confirm)
            unless auto_confirm
              if defined?(ConfirmationGate)
                gate_result = ConfirmationGate.gate(
                  "Repair #{finding.category}",
                  description: finding.message
                ) { true }

                unless gate_result.ok?
                  skipped += 1
                  next
                end
              end
            end

            # Step 4: Attempt fix
            fix_result = attempt_fix(finding)

            if fix_result.ok?
              # Step 5: Run self-test if available
              if respond_to?(:run)
                test_result = run
                unless test_result.ok?
                  # Rollback on test failure
                  rollback_fix(finding)
                  failed += 1

                  # Record failure
                  record_learning(finding, fix_result.value, success: false)
                  next
                end
              end

              repaired += 1

              # Step 6: Record success
              record_learning(finding, fix_result.value, success: true)
            else
              failed += 1
              skipped += 1 if fix_result.error.include?("not available")
            end
          end

          Result.ok(
            repaired: repaired,
            failed: failed,
            skipped: skipped,
            total: findings.size
          )
        end

        private

        def attempt_fix(finding)
          # Try AutoFixer if available
          if defined?(AutoFixer)
            fixer = AutoFixer.new(mode: :moderate)

            if File.exist?(finding.file)
              result = fixer.fix(finding.file)
              return result if result.ok?
            end
          end

          # Try known fix from learning
          if defined?(LearningFeedback)
            if LearningFeedback.known_fix?(finding)
              return LearningFeedback.apply_known(finding)
            end
          end

          Result.err("No fix available for this finding.")
        end

        def rollback_fix(finding)
          # Use Staging rollback if available
          if defined?(Staging)
            staging = Staging.new
            staging.rollback(finding.file)
          end
        end

        def record_learning(finding, fix, success:)
          # Record pattern in learning feedback
          if defined?(LearningFeedback)
            LearningFeedback.record(finding, fix, success: success)
          end
        end
      end
    end
  end
end
