# frozen_string_literal: true

module Commands
  module MiscCommands
    class SelfRun
      DEFAULT_LIMIT = 100
      DEFAULT_FIX_LIMIT = 25

      def self_run(args:, current_user:, project:, dry_run: false, limit: DEFAULT_LIMIT, fix_limit: DEFAULT_FIX_LIMIT)
        return failure_result(message: "You must be signed in to run “self-run”…") unless current_user
        return failure_result(message: "Project is required to run “self-run”…") unless project

        requested_paths = parse_paths(input: args.fetch(:paths, nil))
        violations = collect_violations(project:, paths: requested_paths, limit:)

        return success_result(message: "No violations found—nothing to fix.", violations: [], fixed_count: 0) if violations.empty?

        fixer = args.fetch(:fixer, nil)
        return success_result(message: "Violations collected—no fixer provided.", violations:, fixed_count: 0) unless fixer

        fixed_count, failed = apply_fixes(violations:, fixer:, dry_run:, fix_limit:)

        build_fix_result(
          violations:,
          fixed_count:,
          failed_count: failed.size,
          dry_run:
        )
      end

      def collect_violations(project:, paths:, limit: DEFAULT_LIMIT)
        scope = project.violations.includes(:source_file).order(created_at: :desc)
        scope = scope.where(source_files: { path: paths }) if paths.any?
        scope.limit(limit).to_a
      end

      def apply_fix(violation:, fixer:, dry_run:)
        return { applied: false, message: "Dry-run—no changes applied.", violation: } if dry_run

        applied = begin
          fixer.call(violation:)
        rescue StandardError => e
          return { applied: false, message: "Fix failed—#{e.message}", violation: }
        end

        { applied: !!applied, message: applied ? "Fixed…" : "No change.", violation: }
      end

      private

      def parse_paths(input:)
        raw = input.to_s.strip
        return [] if raw.empty?

        tokens = raw.split(/[,\s]+/)
        tokens.map(&:strip).reject(&:empty?).uniq
      end

      def apply_fixes(violations:, fixer:, dry_run:, fix_limit:)
        failures = []
        fixed = 0

        violations.first(fix_limit).each do |violation|
          result = apply_fix(violation:, fixer:, dry_run:)
          fixed += 1 if result.fetch(:applied, false)
          failures << result unless result.fetch(:applied, false)
        end

        [fixed, failures]
      end

      def build_fix_result(violations:, fixed_count:, failed_count:, dry_run:)
        suffix = dry_run ? " (dry-run)" : ""
        summary = "Processed #{violations.size} violation#{violations.size == 1 ? "" : "s"}—" \
                  "fixed #{fixed_count}, failed #{failed_count}#{suffix}."

        success_result(
          message: summary,
          violations:,
          fixed_count:,
          failed_count:,
          dry_run:
        )
      end

      def success_result(message:, **data)
        { ok: true, message:, **data }
      end

      def failure_result(message:, **data)
        { ok: false, message:, **data }
      end
    end
  end
end