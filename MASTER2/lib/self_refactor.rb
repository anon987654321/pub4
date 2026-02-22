# frozen_string_literal: true

require "fileutils"
require_relative "staging"
require_relative "convergence_tracker"
require_relative "axiom_resolver"
require_relative "dependency_map"

module MASTER
  # Staged self-modification engine. Applies one atomic change at a time
  # using Staging#staged_modify, validates syntax + axioms after each,
  # tracks convergence, and rolls back on any regression.
  module SelfRefactor
    MAX_ITERATIONS = 20
    HARD_LINE_LIMIT = 500

    module_function

    # Main entry point. Iterates until convergence or max_iterations.
    # Returns Result with summary of what changed, what deferred, why stopped.
    def run(max_iterations: MAX_ITERATIONS)
      ConvergenceTracker.reset!
      staging = Staging.new
      files = target_files
      summary = { fixed: [], deferred: [], errors: [], iterations: 0, halted_reason: nil }

      max_iterations.times do |i|
        summary[:iterations] = i + 1
        violations = scan_violations(files)
        fixable, deferred = partition_violations(violations)

        deferred.each { |v| record_deferred(v) }
        summary[:deferred].concat(deferred.map { |v| v[:description] })

        applied = apply_fixes(fixable, staging: staging)
        summary[:fixed].concat(applied[:fixed])
        summary[:errors].concat(applied[:errors])

        remaining = scan_violations(files)
        ConvergenceTracker.record_iteration(
          violations: remaining.size,
          fixed: applied[:fixed].size,
          deferred: deferred.size,
        )

        log_iteration(i + 1)

        if ConvergenceTracker.should_halt?
          summary[:halted_reason] = halt_reason
          break
        end
      end

      summary[:halted_reason] ||= "max_iterations" if summary[:iterations] >= max_iterations
      Result.ok(summary)
    rescue StandardError => e
      Result.err("SelfRefactor crashed: #{e.message}")
    end

    # All lib/**/*.rb files, sorted for deterministic ordering
    def target_files
      Dir.glob(File.join(MASTER.root, "lib", "**", "*.rb"))
    end

    # Scan all files for violations. Returns array of violation hashes.
    # Each: { file:, line:, axiom_id:, description:, fixable: bool }
    def scan_violations(files)
      violations = []
      files.each do |file|
        lines = File.readlines(file)

        # Check hard line limit (SELF_APPLY)
        if lines.size > HARD_LINE_LIMIT
          violations << {
            file: file, line: lines.size, axiom_id: "SELF_APPLY",
            description: "File exceeds #{HARD_LINE_LIMIT} lines (#{lines.size})",
            fixable: false
          }
        end

        # Check frozen_string_literal
        next if lines.first&.strip == "# frozen_string_literal: true"

        violations << {
          file: file, line: 1, axiom_id: "SELF_APPLY",
          description: "Missing frozen_string_literal: true",
          fixable: true
        }
      end
      violations
    end

    # Split violations into fixable vs deferred (blocked by higher axiom)
    def partition_violations(violations)
      fixable = violations.select { |v| v[:fixable] }
      deferred = violations.reject { |v| v[:fixable] }
      [fixable, deferred]
    end

    # Apply fixable violations one at a time through Staging
    def apply_fixes(fixable, staging:)
      result = { fixed: [], errors: [] }
      fixable.each do |violation|
        fix_result = staging.staged_modify(violation[:file]) do |staged_path|
          apply_single_fix(staged_path, violation)
        end
        if fix_result.ok?
          result[:fixed] << violation[:description]
        else
          result[:errors] << "#{violation[:file]}: #{fix_result.error}"
        end
      end
      result
    end

    def apply_single_fix(staged_path, violation)
      case violation[:description]
      when /Missing frozen_string_literal/
        content = File.read(staged_path)
        File.write(staged_path, "# frozen_string_literal: true\n\n#{content}")
      end
    end

    def record_deferred(violation)
      AxiomResolver.defer(
        axiom_id: violation[:axiom_id], file: violation[:file],
        line: violation[:line], reason: violation[:description],
        blocking_axiom: "PRESERVE_FIRST"
      )
    end

    def log_iteration(_n)
      Logging.dmesg_log("self_refactor", message: ConvergenceTracker.summary) if defined?(Logging)
    end

    def halt_reason
      h = ConvergenceTracker.history.last
      return "no_violations" if h[:violations].zero?
      return "stalled" if h[:violation_delta].zero?
      return "low_success_rate" if h[:autofix_success_rate] < 0.1

      "unknown"
    end
  end
end
