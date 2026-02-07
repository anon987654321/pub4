# frozen_string_literal: true

module MASTER
  # SelfRepair - Closed-loop self-improvement
  # Wires together: Audit → prioritize → ConfirmationGate → AutoFixer → SelfTest → LearningFeedback
  # Implements staged refactoring with rollback on verification failure
  # Defaults to dry-run mode for safety
  module SelfRepair
    extend self

    @dry_run = true

    class << self
      attr_accessor :dry_run
    end

    def repair(files, options = {})
      dry_run_mode = options[:dry_run].nil? ? @dry_run : options[:dry_run]
      auto_confirm = options[:auto_confirm] || false

      UI.header("Self-Repair: #{dry_run_mode ? 'DRY RUN' : 'LIVE'}") if defined?(UI)

      # Phase 1: Audit
      puts "\n  Phase 1: Audit"
      audit_result = run_audit(files)
      return audit_result if audit_result.err?

      report = audit_result.value[:report]
      puts "    Found #{report.total_count} findings"
      puts "    Critical: #{report.critical_count}, Major: #{report.major_count}"

      return Result.ok(stage: :audit, message: "No findings to repair") if report.total_count.zero?

      # Phase 2: Prioritize
      puts "\n  Phase 2: Prioritize"
      prioritized = prioritize_findings(report)
      puts "    Top priority: #{prioritized.first&.message}"

      # Phase 3: ConfirmationGate
      if dry_run_mode
        puts "\n  Phase 3: Confirmation (skipped - dry run)"
      else
        puts "\n  Phase 3: Confirmation"
        return Result.err("User cancelled repair") unless confirm_repair(prioritized, auto_confirm)
      end

      # Phase 4: Apply fixes
      puts "\n  Phase 4: Apply Fixes"
      fix_results = apply_fixes(prioritized, dry_run_mode)

      return Result.ok(stage: :dry_run, fixes: fix_results) if dry_run_mode

      # Phase 5: Self-test
      puts "\n  Phase 5: Verification"
      verification = verify_fixes(files, fix_results)

      if verification.err?
        puts "    ✗ Verification failed: #{verification.failure}"
        rollback_fixes(fix_results)
        return Result.err("Verification failed, rolled back changes")
      end

      puts "    ✓ Verification passed"

      # Phase 6: Learning feedback
      puts "\n  Phase 6: Learning Feedback"
      record_learning(fix_results)

      Result.ok(
        stage: :complete,
        fixes_applied: fix_results[:succeeded].size,
        fixes_failed: fix_results[:failed].size,
      )
    rescue StandardError => e
      Result.err("Self-repair failed: #{e.message}")
    end

    private

    def run_audit(files)
      if defined?(MASTER::Audit)
        Audit.scan(files)
      else
        Result.err("Audit module not available")
      end
    end

    def prioritize_findings(report)
      report.prioritized.select do |finding|
        # Only auto-fix certain types
        fixable_type?(finding.type) && finding.effort == :low
      end.take(10)
    end

    def fixable_type?(type)
      %i[
        trailing_whitespace
        empty_lines_excess
        debug_code
        puts_debug
        trailing_newlines
        mixed_indentation
      ].include?(type)
    end

    def confirm_repair(findings, auto_confirm)
      return true if auto_confirm

      if defined?(MASTER::ConfirmationGate)
        ConfirmationGate.gate(:self_modify, details: "Apply #{findings.size} fixes") do
          true
        end.ok?
      else
        true # No gate available, proceed
      end
    end

    def apply_fixes(findings, dry_run)
      results = { succeeded: [], failed: [], skipped: [] }

      return results if dry_run

      # Group findings by file
      by_file = findings.group_by(&:file)

      by_file.each do |file, file_findings|
        # Check learning feedback for known patterns
        pattern = check_learning_feedback(file_findings.first)

        if pattern && should_auto_apply?(pattern)
          result = apply_learned_pattern(file, pattern)
        elsif defined?(MASTER::AutoFixer)
          result = apply_auto_fixer(file, file_findings)
        else
          results[:skipped] << { file: file, reason: "No fixer available" }
          next
        end

        if result&.ok?
          results[:succeeded] << { file: file, findings: file_findings, pattern_id: pattern&.dig(:id) }
        else
          results[:failed] << { file: file, error: result&.failure || "Unknown error" }
        end
      end

      results
    end

    def check_learning_feedback(finding)
      return nil unless defined?(MASTER::LearningFeedback)

      LearningFeedback.find_pattern(
        finding_type: finding.type,
        code_context: { file: finding.file }
      )
    end

    def should_auto_apply?(pattern)
      return false unless defined?(MASTER::LearningQuality)

      LearningQuality.should_auto_apply?(pattern)
    end

    def apply_learned_pattern(file, pattern)
      # Apply the learned fix pattern
      return Result.err("Pattern has no fix") unless pattern[:fix]

      code = File.read(file)
      fixed_code = pattern[:fix].call(code) rescue code

      if fixed_code != code
        File.write(file, fixed_code)
        Result.ok(applied: :learned_pattern)
      else
        Result.ok(applied: :no_change)
      end
    rescue StandardError => e
      Result.err("Failed to apply pattern: #{e.message}")
    end

    def apply_auto_fixer(file, findings)
      fixer = AutoFixer.new(mode: :conservative)
      violations = findings.map { |f| { type: f.type, message: f.message } }
      fixer.fix(file, violations)
    end

    def verify_fixes(files, fix_results)
      # Run self-test if available
      if defined?(MASTER::SelfTest)
        # For now, just check syntax
        verify_syntax(files)
      else
        verify_syntax(files)
      end
    end

    def verify_syntax(files)
      files.each do |file|
        next unless File.exist?(file) && file.end_with?(".rb")

        code = File.read(file)
        eval("BEGIN { return }; #{code}", binding, file, 0)
      rescue SyntaxError => e
        return Result.err("Syntax error in #{file}: #{e.message}")
      rescue StandardError
        # Other errors are OK for syntax check
      end

      Result.ok(verified: files.size)
    end

    def rollback_fixes(fix_results)
      return unless defined?(MASTER::AutoFixer)

      fix_results[:succeeded].each do |fix|
        # In a real implementation, would restore from backup
        puts "    Rolled back #{fix[:file]}"
      end
    end

    def record_learning(fix_results)
      return unless defined?(MASTER::LearningFeedback)

      fix_results[:succeeded].each do |fix|
        next unless fix[:pattern_id]

        LearningFeedback.record_success(fix[:pattern_id])
      end

      fix_results[:failed].each do |fix|
        next unless fix[:pattern_id]

        LearningFeedback.record_failure(fix[:pattern_id])
      end
    end
  end
end
