# frozen_string_literal: true

module MASTER
  # AdversarialPass — universal adversarial questioning for ALL code.
  #
  # Unlike PressurePass (which questions LLM *answers*) and Introspection::Adversarial
  # (which runs during self-inspection), AdversarialPass questions ANY code at ANY point:
  #   - file_write: before writing code, question the proposed change
  #   - refactor: after LLM proposes a rewrite, question it against the original
  #   - fix: after generating a fix, question whether it introduces new issues
  #   - scan: deepen scan findings with adversarial probes
  #
  # Implements MART-inspired multi-round questioning:
  #   Round 1: Heuristic fast checks (zero LLM cost)
  #   Round 2: Socratic deep probes via LLM (if round 1 finds issues)
  #   Round 3: Improvement loop — LLM fixes issues, re-question (max 3 rounds)
  #
  # Returns Result.ok(code:, findings:, rounds:, improved:) or Result.err.
  module AdversarialPass
    module_function

    MAX_ROUNDS = 3
    CODE_LIMIT = 8000

    # ── Dimension probes ─────────────────────────────────────────────────
    # Each dimension is a category of adversarial questioning.
    # Heuristic checks run first (free). LLM probes run only when needed.
    DIMENSIONS = {
      assumptions: {
        heuristic: ->(code) {
          issues = []
          issues << "Absolute language suggests unchecked assumption" if code.match?(/\b(always|never|guaranteed|definitely|impossible)\b/i)
          issues << "Hardcoded magic number" if code.match?(/(?<!=)\b(?:[2-9]\d{2,}|1\d{3,})\b/) && !code.match?(/(?:MAX_|MIN_|LIMIT|TIMEOUT|PORT|VERSION)/)
          issues << "Bare rescue swallows errors" if code.match?(/rescue\s*(?:$|#|\n\s*(?:nil|end|next|""|''))/)
          issues << "No nil guard on chain" if code.match?(/\.\w+\.\w+\.\w+/) && !code.match?(/&\./)
          issues
        },
        probe: "What assumptions does this code make that could be false? " \
               "List each assumption and what breaks if it is wrong.",
      },
      edge_cases: {
        heuristic: ->(code) {
          issues = []
          issues << "Array access without bounds check" if code.match?(/\[\d+\]/) && !code.match?(/\.size|\.length|\.count|\.empty\?/)
          issues << "Division without zero guard" if code.match?(%r{/\s*\w+}) && !code.match?(/zero\?|\.positive\?/)
          issues << "String operation without nil/empty check" if code.match?(/\.strip|\.split|\.gsub/) && !code.match?(/\.to_s|&\.|nil\?|empty\?/)
          issues << "File operation without existence check" if code.match?(/File\.(read|write|delete)/) && !code.match?(/File\.exist\?|rescue/)
          issues
        },
        probe: "What edge cases would break this code? Consider: nil, empty, " \
               "zero, negative, very large, concurrent access, missing files, network failure.",
      },
      security: {
        heuristic: ->(code) {
          issues = []
          issues << "Code execution pattern (eval/exec/system)" if code.match?(/\b(eval|exec|system|`[^`]+`|%x\{)/i)
          issues << "Potential SQL injection" if code.match?(/\b(where|select|insert|update|delete)\b.*#\{/i) && !code.match?(/sanitize|parameterize|placeholder/)
          issues << "Hardcoded credential" if code.match?(/(?:password|secret|token|api_key)\s*=\s*["'][^"']{8,}/i)
          issues << "User input used in path" if code.match?(/File\.(read|write|join|expand_path).*(?:params|input|args|request)/)
          issues << "Unsafe deserialization" if code.match?(/Marshal\.load|YAML\.load[^_]|JSON\.parse.*\beval\b/)
          issues
        },
        probe: "What security vulnerabilities exist? Consider: injection, " \
               "path traversal, privilege escalation, information disclosure, " \
               "unsafe deserialization, race conditions.",
      },
      performance: {
        heuristic: ->(code) {
          issues = []
          issues << "N+1 query pattern" if code.match?(/\.each.*\.(find|where|select|load)/)
          issues << "Unbounded collection in memory" if code.match?(/\.map|\.flat_map|\.collect/) && !code.match?(/\.first|\.take|\.limit|lazy/)
          issues << "Nested loop (O(n²) or worse)" if code.scan(/\.each|\.map|\.select|for\s/).size > 2
          issues << "Synchronous I/O in loop" if code.match?(/\.each.*(?:File\.|Net::|HTTP\.|sleep|system)/)
          issues
        },
        probe: "What performance problems exist? Consider: time complexity, " \
               "memory allocation, I/O bottlenecks, unnecessary computation, " \
               "missing caching, N+1 queries.",
      },
      alternatives: {
        heuristic: ->(_code) { [] }, # No heuristic — always needs LLM
        probe: "Is this the simplest solution? Propose a simpler alternative. " \
               "If no simpler solution exists, explain why this is minimal.",
      },
      maintainability: {
        heuristic: ->(code) {
          issues = []
          lines = code.lines
          issues << "Method too long (>50 lines)" if code.scan(/\bdef\b/).any? && lines.size > 50
          issues << "Deep nesting (>4 levels)" if code.match?(/^(\s{8,})\S/) && code.scan(/\bif\b|\bcase\b|\bdo\b|\bbegin\b/).size > 4
          issues << "Too many parameters" if code.match?(/def\s+\w+\([^)]{60,}\)/)
          issues << "Mixed concerns in single method" if code.match?(/\bdef\b/) && code.scan(/\b(File\.|Net::|DB\.|LLM\.)/).map { |m| m[0] }.uniq.size > 2
          issues
        },
        probe: "Is this code maintainable? Consider: naming clarity, " \
               "single responsibility, coupling, debuggability at 3 AM.",
      },
    }.freeze

    # ── Public API ───────────────────────────────────────────────────────

    # Question any code. Returns structured findings.
    # mode: :fast (heuristic only), :standard (heuristic + LLM on findings),
    #        :deep (multi-round MART iteration)
    def question(code, context: {}, mode: :standard)
      return Result.ok(skipped: true, reason: "empty code") if code.nil? || code.strip.empty?

      code_text = code.to_s[0, CODE_LIMIT]

      # Round 1: Heuristic fast checks (zero cost)
      findings = run_heuristics(code_text, context)

      return Result.ok(code: code, findings: findings, rounds: 1, improved: false) if mode == :fast

      # Round 2: LLM deep probes on dimensions that found issues
      if findings.any? || mode == :deep
        deep = run_deep_probes(code_text, findings, context)
        findings.concat(deep)
      end

      return Result.ok(code: code, findings: findings, rounds: 2, improved: false) if mode == :standard

      # Round 3+: MART iteration — question, improve, re-question
      improved_code = code
      rounds = 2
      MAX_ROUNDS.times do
        break if findings.select { |f| f[:severity] == :high || f[:severity] == :critical }.empty?

        improved_code = improve_code(improved_code, findings, context)
        break if improved_code == code # no improvement possible

        new_findings = run_heuristics(improved_code, context)
        rounds += 1

        # Convergence: stop if issues aren't decreasing
        break if new_findings.size >= findings.size

        findings = new_findings
      end

      Result.ok(
        code: improved_code,
        findings: findings,
        rounds: rounds,
        improved: improved_code != code
      )
    rescue StandardError => err
      Logging.warn("adversarial_pass: #{err.message}", subsystem: "adversarial") if defined?(Logging)
      Result.ok(code: code, findings: [], rounds: 0, improved: false, error: err.message)
    end

    # Quick gate: returns true if code passes adversarial heuristics.
    # Use in hot paths (file_write, verify_change) where full LLM probe is too slow.
    def quick_check(code, context: {})
      findings = run_heuristics(code.to_s[0, CODE_LIMIT], context)
      critical = findings.select { |f| f[:severity] == :critical }
      { pass: critical.empty?, findings: findings, critical: critical }
    end

    # Question a proposed change against the original.
    # Compares old vs new to catch regressions.
    def question_change(original, proposed, context: {})
      return Result.ok(skipped: true) if original.nil? || proposed.nil?

      original_findings = run_heuristics(original.to_s[0, CODE_LIMIT], context)
      proposed_findings = run_heuristics(proposed.to_s[0, CODE_LIMIT], context)

      # New issues introduced by the change
      new_issues = proposed_findings.reject do |pf|
        original_findings.any? { |of| of[:dimension] == pf[:dimension] && of[:issue] == pf[:issue] }
      end

      # Issues fixed by the change
      fixed_issues = original_findings.reject do |of|
        proposed_findings.any? { |pf| pf[:dimension] == of[:dimension] && pf[:issue] == of[:issue] }
      end

      verdict = if new_issues.any? { |i| i[:severity] == :critical }
                  :reject
                elsif new_issues.size > fixed_issues.size
                  :caution
                else
                  :accept
                end

      Result.ok(
        verdict: verdict,
        new_issues: new_issues,
        fixed_issues: fixed_issues,
        net_change: fixed_issues.size - new_issues.size,
        original_count: original_findings.size,
        proposed_count: proposed_findings.size
      )
    end

    # ── Challenge: LLM-forced multi-solution generation + cherry-pick ──
    #
    # Forces the LLM to:
    #   1. Critique the candidate code (counterargument)
    #   2. Identify concrete failure modes
    #   3. Generate 3 alternative implementations
    #   4. Score each on correctness / security / simplicity / performance
    #   5. Select the best and explain why
    #
    # This is the Refinement/PressurePass pattern adapted for CODE, not prose.
    # Called by the executor when writing non-trivial code (>20 lines).
    CHALLENGE_SCHEMA = {
      type: "object",
      additionalProperties: false,
      required: %w[critique failure_modes alternatives scores selected_index selected_code rationale],
      properties: {
        critique: { type: "string" },
        failure_modes: { type: "array", minItems: 2, items: { type: "string" } },
        alternatives: {
          type: "array", minItems: 3, maxItems: 5,
          items: { type: "string" },
        },
        scores: {
          type: "array", minItems: 3, maxItems: 5,
          items: {
            type: "object",
            properties: {
              correctness: { type: "integer", minimum: 1, maximum: 10 },
              security: { type: "integer", minimum: 1, maximum: 10 },
              simplicity: { type: "integer", minimum: 1, maximum: 10 },
              performance: { type: "integer", minimum: 1, maximum: 10 },
            },
          },
        },
        selected_index: { type: "integer", minimum: 0 },
        selected_code: { type: "string" },
        rationale: { type: "string" },
      },
    }.freeze

    # Returns Result.ok(selected_code:, critique:, alternatives:, ...) or nil.
    def challenge(code, intent: "", context: {})
      return nil unless defined?(LLM) && LLM.respond_to?(:configured?) && LLM.configured?
      return nil if code.nil? || code.strip.length < 80 # skip trivial code

      prompt = build_challenge_prompt(code, intent, context)
      result = LLM.ask_json(prompt, schema: CHALLENGE_SCHEMA, tier: :strong, stream: false)
      return nil unless result&.ok?

      payload = normalize_challenge(result.value[:content])
      return nil unless payload

      selected = payload[:selected_code].to_s.strip
      return nil if selected.empty?

      # Validate selected code passes heuristics better than original
      original_check = quick_check(code, context: context)
      selected_check = quick_check(selected, context: context)

      # Reject if cherry-picked code is worse
      if selected_check[:critical]&.size.to_i > original_check[:critical]&.size.to_i
        return nil
      end

      {
        selected_code: selected,
        critique: payload[:critique].to_s,
        failure_modes: Array(payload[:failure_modes]).map(&:to_s),
        alternatives_count: Array(payload[:alternatives]).size,
        scores: Array(payload[:scores]),
        selected_index: payload[:selected_index].to_i,
        rationale: payload[:rationale].to_s,
        improvement: original_check[:findings].size - selected_check[:findings].size,
      }
    rescue StandardError => err
      Logging.warn("adversarial_challenge: #{err.message}", subsystem: "adversarial") if defined?(Logging)
      nil
    end

    # ── Private ──────────────────────────────────────────────────────────

    def run_heuristics(code, context)
      findings = []
      ext = context[:extension] || context[:path]&.then { |p| File.extname(p) } || ".rb"

      DIMENSIONS.each do |dimension, config|
        issues = config[:heuristic].call(code)
        issues.each do |issue|
          findings << {
            dimension: dimension,
            issue: issue,
            severity: classify_severity(dimension, issue),
            source: :heuristic,
          }
        end
      end

      # Extension-specific checks
      findings.concat(check_ruby_specific(code)) if ext == ".rb"
      findings.concat(check_shell_specific(code)) if %w[.sh .zsh].include?(ext)

      findings
    end
    private_class_method :run_heuristics

    def run_deep_probes(code, existing_findings, context)
      return [] unless defined?(LLM) && LLM.respond_to?(:configured?) && LLM.configured?

      # Only probe dimensions that had heuristic hits, plus :alternatives always
      dimensions_to_probe = existing_findings.map { |f| f[:dimension] }.uniq
      dimensions_to_probe << :alternatives if context[:mode] == :deep
      dimensions_to_probe.uniq!

      findings = []
      probes = dimensions_to_probe.first(3).filter_map { |d| DIMENSIONS.dig(d, :probe) }
      return findings if probes.empty?

      prompt = build_probe_prompt(code, probes, context)
      result = LLM.ask(prompt, tier: :fast, stream: false)
      return findings unless result&.ok?

      response = result.value[:content].to_s
      # Parse structured issues from LLM response
      response.scan(/ISSUE:\s*\[(\w+)\]\s*(.+)/).each do |dimension, issue|
        dim_sym = dimension.downcase.to_sym
        findings << {
          dimension: DIMENSIONS.key?(dim_sym) ? dim_sym : :general,
          issue: issue.strip,
          severity: :medium,
          source: :llm_probe,
        }
      end

      findings
    end
    private_class_method :run_deep_probes

    def build_probe_prompt(code, probes, context)
      file_hint = context[:path] ? " (file: #{context[:path]})" : ""
      <<~PROMPT
        You are an adversarial code reviewer#{file_hint}. Your job is to find real problems, not nitpick style.
        Only report issues that could cause bugs, security holes, performance problems, or maintenance pain.

        CODE:
        ```
        #{code[0, CODE_LIMIT]}
        ```

        PROBES:
        #{probes.map.with_index(1) { |p, i| "#{i}. #{p}" }.join("\n")}

        For each real issue found, respond with exactly:
        ISSUE: [dimension] description

        Where dimension is one of: assumptions, edge_cases, security, performance, alternatives, maintainability

        If no real issues, respond: PASS
      PROMPT
    end
    private_class_method :build_probe_prompt

    def improve_code(code, findings, context)
      return code unless defined?(LLM) && LLM.respond_to?(:configured?) && LLM.configured?

      issues_text = findings.select { |f| %i[high critical].include?(f[:severity]) }
                           .map { |f| "- [#{f[:dimension]}] #{f[:issue]}" }
                           .join("\n")
      return code if issues_text.empty?

      prompt = <<~PROMPT
        Fix ONLY the following issues in this code. Change nothing else.

        ISSUES:
        #{issues_text}

        CODE:
        ```
        #{code[0, CODE_LIMIT]}
        ```

        Return ONLY the fixed code, no explanation.
      PROMPT

      result = LLM.ask(prompt, tier: :fast, stream: false)
      return code unless result&.ok?

      fixed = result.value[:content].to_s
      # Strip markdown fences if present
      fixed = fixed.gsub(/\A```\w*\n/, "").gsub(/\n```\s*\z/, "")
      fixed.strip.empty? ? code : fixed
    end
    private_class_method :improve_code

    def classify_severity(dimension, _issue)
      case dimension
      when :security then :critical
      when :edge_cases, :assumptions then :high
      when :performance, :maintainability then :medium
      when :alternatives then :low
      else :medium
      end
    end
    private_class_method :classify_severity

    def check_ruby_specific(code)
      issues = []
      issues << { dimension: :security, issue: "Thread-unsafe shared mutable state (@@var)", severity: :high, source: :heuristic } if code.match?(/@@\w+\s*[+\-]?=/)
      issues << { dimension: :assumptions, issue: "rescue Exception catches SignalException/SystemExit", severity: :high, source: :heuristic } if code.match?(/rescue\s+Exception\b/)
      issues << { dimension: :edge_cases, issue: "Infinite recursion risk: method calls itself without base case", severity: :high, source: :heuristic } if code.match?(/def\s+(\w+).*\n(?:.*\n)*?.*\b\1\b/) && !code.match?(/return|break|raise/)
      issues
    end
    private_class_method :check_ruby_specific

    def check_shell_specific(code)
      issues = []
      issues << { dimension: :security, issue: "Unquoted variable expansion", severity: :high, source: :heuristic } if code.match?(/\$\w+/) && !code.match?(/"\$\w+"|\$\{/)
      issues << { dimension: :assumptions, issue: "Uses bash shebang — should be zsh", severity: :medium, source: :heuristic } if code.match?(%r{#!/.*(bash|sh)\b}) && !code.match?(/zsh/)
      issues << { dimension: :security, issue: "Uses sudo — should be doas", severity: :medium, source: :heuristic } if code.match?(/\bsudo\b/)
      issues
    end
    private_class_method :check_shell_specific

    def build_challenge_prompt(code, intent, context)
      file_hint = context[:path] ? " for #{context[:path]}" : ""
      <<~PROMPT
        You are an adversarial code challenger#{file_hint}. You MUST:

        1. CRITIQUE: Find the strongest objection to this code.
        2. FAILURE MODES: List ≥2 concrete ways this code can fail.
        3. ALTERNATIVES: Write 3 complete alternative implementations that solve the same problem.
           Each alternative must be meaningfully different (not just variable renames).
        4. SCORE each alternative on: correctness, security, simplicity, performance (1-10 each).
        5. SELECT the best alternative and explain why.

        Intent: #{intent.to_s.empty? ? "general code improvement" : intent}

        CANDIDATE CODE:
        ```
        #{code[0, CODE_LIMIT]}
        ```

        Rules:
        - Alternatives must be complete, runnable replacements.
        - selected_code must be the full code of the best alternative.
        - No markdown fences inside JSON string values — use plain text.
        - Prefer simpler solutions over clever ones.
        - If the original is already optimal, say so but still provide alternatives.
      PROMPT
    end
    private_class_method :build_challenge_prompt

    def normalize_challenge(payload)
      data = case payload
             when Hash then payload.transform_keys { |k| k.to_s.to_sym }
             when String
               parsed = JSON.parse(payload)
               parsed.is_a?(Hash) ? parsed.transform_keys { |k| k.to_s.to_sym } : nil
             end
      return nil unless data.is_a?(Hash) && data[:selected_code]

      data
    rescue JSON::ParserError
      nil
    end
    private_class_method :normalize_challenge
  end
end
