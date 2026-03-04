# frozen_string_literal: true

require "time"

module Commands
  class CodeCommands
    TIMESTAMP_FORMAT = "%Y-%m-%dT%H:%M:%SZ"
    DEFAULT_CANDIDATE_LIMIT = 10
    MAX_PATCH_BYTES = 150_000
    UI_QUOTE_LEFT = "“"
    UI_QUOTE_RIGHT = "”"
    UI_EM_DASH = "—"
    UI_ELLIPSIS = "…"

    def scan_code(args:, current_user:, now: Time.now.utc)
      arg_string = args.to_s.strip
      return failure(message: "Missing scan target#{UI_ELLIPSIS}") if arg_string.empty?

      target = parse_refactor_target(arg_string: arg_string)
      return failure(message: "Unknown scan target #{UI_QUOTE_LEFT}#{arg_string}#{UI_QUOTE_RIGHT}") unless target

      scan = nil
      begin
        scan = CodeScanService.call(target: target, requested_by: current_user, requested_at: now)
      rescue StandardError => e
        Logging.warn("scan_code failed#{UI_EM_DASH}target=#{arg_string} error=#{e.class}: #{e.message}")
        return failure(message: "Scan failed#{UI_ELLIPSIS}")
      end

      success(
        message: "Scan queued#{UI_EM_DASH}#{target.label} at #{now.strftime(TIMESTAMP_FORMAT)}",
        payload: { scan_id: scan.id, target: target.label }
      )
    end

    def opportunities(args:, current_user:)
      arg_string = args.to_s.strip
      return failure(message: "Missing target#{UI_ELLIPSIS}") if arg_string.empty?

      target = parse_refactor_target(arg_string: arg_string)
      return failure(message: "Unknown target #{UI_QUOTE_LEFT}#{arg_string}#{UI_QUOTE_RIGHT}") unless target

      findings = nil
      begin
        findings = OpportunityFinder.call(target: target, requested_by: current_user)
      rescue StandardError => e
        Logging.warn("opportunities failed#{UI_EM_DASH}target=#{arg_string} error=#{e.class}: #{e.message}")
        return failure(message: "Couldn’t load opportunities#{UI_ELLIPSIS}")
      end

      success(
        message: "Found #{findings.size} opportunities#{UI_ELLIPSIS}",
        payload: { target: target.label, opportunities: findings }
      )
    end

    def autofix(args:, current_user:, candidate_limit: DEFAULT_CANDIDATE_LIMIT)
      arg_string = args.to_s.strip
      return failure(message: "Missing target#{UI_ELLIPSIS}") if arg_string.empty?

      target = parse_refactor_target(arg_string: arg_string)
      return failure(message: "Unknown target #{UI_QUOTE_LEFT}#{arg_string}#{UI_QUOTE_RIGHT}") unless target

      begin
        candidates = FixCandidateGenerator.call(target: target, requested_by: current_user).first(candidate_limit)
      rescue StandardError => e
        Logging.warn("autofix candidate generation failed#{UI_EM_DASH}target=#{arg_string} error=#{e.class}: #{e.message}")
        return failure(message: "Couldn’t generate fixes#{UI_ELLIPSIS}")
      end

      best_fix = best_candidate_fix(
        candidates: candidates,
        target: target,
        requested_by: current_user
      )
      return failure(message: "No safe fix found#{UI_ELLIPSIS}") unless best_fix

      applied = nil
      begin
        applied = FixApplier.call(fix: best_fix, requested_by: current_user)
      rescue StandardError => e
        Logging.warn("autofix apply failed#{UI_EM_DASH}target=#{target.label} error=#{e.class}: #{e.message}")
        return failure(message: "Fix failed to apply#{UI_ELLIPSIS}")
      end

      success(
        message: "Applied fix#{UI_EM_DASH}#{applied.summary}",
        payload: { target: target.label, fix_id: applied.id }
      )
    end

    def evolve(args:, current_user:, iterations: 3)
      arg_string = args.to_s.strip
      return failure(message: "Missing target#{UI_ELLIPSIS}") if arg_string.empty?
      return failure(message: "Iterations must be > 0") unless iterations.to_i.positive?

      target = parse_refactor_target(arg_string: arg_string)
      return failure(message: "Unknown target #{UI_QUOTE_LEFT}#{arg_string}#{UI_QUOTE_RIGHT}") unless target

      results = []
      iterations.to_i.times do |i|
        run = nil
        begin
          run = EvolutionRunner.call(target: target, requested_by: current_user, iteration: i + 1)
        rescue StandardError => e
          Logging.warn("evolve failed#{UI_EM_DASH}target=#{target.label} iteration=#{i + 1} error=#{e.class}: #{e.message}")
          return failure(message: "Evolution failed on iteration #{i + 1}#{UI_ELLIPSIS}", payload: { results: results })
        end
        results << run
      end

      success(
        message: "Evolution complete#{UI_EM_DASH}#{results.size} iterations",
        payload: { target: target.label, results: results }
      )
    end

    def print_deps(args:, current_user:)
      arg_string = args.to_s.strip
      return failure(message: "Missing target#{UI_ELLIPSIS}") if arg_string.empty?

      target = parse_refactor_target(arg_string: arg_string)
      return failure(message: "Unknown target #{UI_QUOTE_LEFT}#{arg_string}#{UI_QUOTE_RIGHT}") unless target

      deps = nil
      begin
        deps = DependencyGraphService.call(target: target, requested_by: current_user)
      rescue StandardError => e
        Logging.warn("print_deps failed#{UI_EM_DASH}target=#{target.label} error=#{e.class}: #{e.message}")
        return failure(message: "Couldn’t compute dependencies#{UI_ELLIPSIS}")
      end

      success(
        message: "Dependencies ready#{UI_ELLIPSIS}",
        payload: { target: target.label, dependency_graph: deps }
      )
    end

    def run_converge(args:, current_user:)
      arg_string = args.to_s.strip
      return failure(message: "Missing target#{UI_ELLIPSIS}") if arg_string.empty?

      target = parse_refactor_target(arg_string: arg_string)
      return failure(message: "Unknown target #{UI_QUOTE_LEFT}#{arg_string}#{UI_QUOTE_RIGHT}") unless target

      job = nil
      begin
        job = ConvergeRunner.call(target: target, requested_by: current_user)
      rescue StandardError => e
        Logging.warn("run_converge failed#{UI_EM_DASH}target=#{target.label} error=#{e.class}: #{e.message}")
        return failure(message: "Converge failed#{UI_ELLIPSIS}")
      end

      success(
        message: "Converge started#{UI_EM_DASH}job #{job.id}",
        payload: { target: target.label, job_id: job.id }
      )
    end

    private

    def parse_refactor_target(arg_string:)
      parts = arg_string.split(/\s+/)
      kind = parts.fetch(0, nil)
      identifier = parts.fetch(1, nil)
      return nil if kind.nil? || identifier.nil?

      case kind.downcase
      when "file"
        RefactorTarget.file(path: identifier)
      when "class"
        RefactorTarget.klass(name: identifier)
      when "package"
        RefactorTarget.package(name: identifier)
      else
        nil
      end
    rescue StandardError => e
      Logging.warn("parse_refactor_target failed#{UI_EM_DASH}arg=#{arg_string.inspect} error=#{e.class}: #{e.message}")
      nil
    end

    def best_candidate_fix(candidates:, target:, requested_by:)
      return nil if candidates.nil? || candidates.empty?

      scored = candidates.map do |candidate_fix|
        score = score_candidate(
          candidate_fix: candidate_fix,
          target: target,
          requested_by: requested_by
        )
        [candidate_fix, score]
      end

      best_pair = scored.compact.max_by { |(_candidate, score)| score }
      best_pair&.first
    rescue StandardError => e
      Logging.warn("best_candidate_fix failed#{UI_EM_DASH}target=#{target&.label} error=#{e.class}: #{e.message}")
      nil
    end

    def score_candidate(candidate_fix:, target:, requested_by:)
      metadata = candidate_fix.metadata || {}
      patch_bytes = metadata.fetch(:patch_bytes, 0).to_i
      return -Float::INFINITY if patch_bytes > MAX_PATCH_BYTES

      violation_count = metadata.fetch(:violation_count, 0).to_i
      cost_ratio = metadata.fetch(:cost_ratio, 1.0).to_f

      risk_penalty = begin
        RiskAssessor.call(fix: candidate_fix, target: target, requested_by: requested_by)
      rescue StandardError => e
        Logging.warn("score_candidate risk assess failed#{UI_EM_DASH}target=#{target&.label} error=#{e.class}: #{e.message}")
        return -Float::INFINITY
      end

      improvement_score = violation_count / [cost_ratio, 0.01].max
      improvement_score - risk_penalty.to_f
    end

    def success(message:, payload: {})
      { ok: true, message: message, payload: payload }
    end

    def failure(message:, payload: {})
      { ok: false, message: message, payload: payload }
    end
  end
end