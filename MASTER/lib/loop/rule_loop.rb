# frozen_string_literal: true

require "tempfile"
require_relative "../ground/atomic_write"
require_relative "constants"
require_relative "fix_helpers"
require_relative "patch_applier"

module Master
  module Loop
  # Single-pass fixer for one rule across a set of files.
  # SuperLoop owns the outer convergence loop; RuleLoop fixes one batch per call.
  #
  # Fix routing (per violation severity + file size):
  #   error tier  → council_fix   (3-reviewer veto before apply)
  #   large file  → diff_fix      (unified diff patch; arch #5)
  #   small file  → genetic_fix   (N candidates, rescan, best wins; arch #9)
  class RuleLoop
    RATE_LIMIT_SLEEP = 10
    MAX_FIX_RETRIES  = 2
    CANDIDATE_COUNT  = 3 # arch #9

    SEVERITY_RANK = Master::SEVERITY_RANK
    MIN_SEVERITY  = SEVERITY_RANK[:warning]

    include Master::Ground::AtomicWrite
    include Master::Loop::FixHelpers

    def initialize(rule:, agent:, scanner:, root:, bus: nil, learnings: nil)
      @rule      = rule
      @agent     = agent
      @scanner   = scanner
      @root      = root
      @bus       = bus
      @learnings = learnings
    end

    def injected_preamble=(text)
      @injected_preamble = text
    end

    # One pass: scan → fix each violating file once → return { fixed:, status: }.
    def run_once(files)
      violations = scan_files(files)
      return { fixed: 0, status: :clean } if violations.empty?

      fixed = fix_batch(violations)
      status = fixed > 0 ? :fixed : :stuck
      record_outcomes(files, fixed > 0 ? :fixed : :stuck)
      @bus&.publish("rule_loop:pass", rule: @rule.id, violations: violations.size, fixed:, status:)
      { fixed:, status: }
    rescue StandardError => e
      @bus&.publish("rule_loop:error", rule: @rule.id, error: e.message)
      { fixed: 0, status: :error }
    end

    private

    def scan_files(files)
      files.flat_map do |path|
        next [] unless File.exist?(path)
        result = @scanner.scan(path, rules: [@rule])
        next [] unless result.ok?
        ext = File.extname(path).downcase
        result.value!
              .select { |f| (SEVERITY_RANK[f[:severity]] || 0) >= MIN_SEVERITY }
              .map    { |f| f.merge(file: path, ext:) }
      end
    end

    def fix_batch(violations)
      fixed = 0
      violations.uniq { |v| v[:file] }.each do |v|
        new_src = v[:severity].to_sym == :error ? council_fix(v) : request_fix(v)
        apply(v[:file], new_src) && (fixed += 1) if new_src
      end
      fixed
    end

    # Architecture #6: three-reviewer veto for error-tier violations.
    def council_fix(violation)
      path = violation[:file]
      return unless File.exist?(path)
      src    = File.read(path, encoding: "UTF-8")
      prompt = <<~PROMPT
        #{preamble}

        File: #{File.basename(path)}
        Rule violated (severity: ERROR): #{violation[:rule]}
        Line #{violation[:line]}: #{violation[:message]}
        #{violation[:fix].to_s.empty? ? "" : "Suggested fix: #{violation[:fix]}"}

        Three reviewers assess before any fix is applied:
        As Skeptic: Is this a real violation or a false positive? What is the blast radius?
        As Security: Does this create an attack surface? What must the fix preserve?
        As Maintainer: What is the minimum change that eliminates the violation without drift?

        Produce the corrected file only if all three agree the fix is safe.
        If any reviewer would block, return exactly: UNCHANGED

        ```
        #{src}
        ```
      PROMPT
      MAX_FIX_RETRIES.times do |attempt|
        sleep RATE_LIMIT_SLEEP * attempt if attempt.positive?
        response = @agent.ask(prompt).to_s
        return nil if response.strip == "UNCHANGED"
        code = extract_code(response, File.extname(path).downcase)
        return code if code && code.strip != src.strip
      rescue StandardError => e
        next if Master::Loop::Constants::TRANSIENT_RE.match?(e.message.to_s)
        @bus&.publish("rule_loop:council_error", rule: @rule.id, file: path, error: e.message[0, 120])
        return nil
      end
      nil
    end

    # Architecture #5 + #9: diff for large files, genetic candidates for small.
    def request_fix(violation)
      path = violation[:file]
      return unless File.exist?(path)
      src = File.read(path, encoding: "UTF-8")
      src.bytesize > PatchApplier::DIFF_THRESHOLD ? diff_fix(violation, src, path) : genetic_fix(violation, src, path)
    end

    # Architecture #5: unified diff patch — safe on large files.
    def diff_fix(violation, src, path)
      prompt = build_diff_prompt(violation, src, path)
      MAX_FIX_RETRIES.times do |attempt|
        sleep RATE_LIMIT_SLEEP * attempt if attempt.positive?
        response = @agent.ask(prompt).to_s
        next if response.strip == "UNCHANGED"
        result = PatchApplier.apply(src, response)
        return result.source if result.is_a?(PatchApplier::Success)
      rescue StandardError => e
        next if Master::Loop::Constants::TRANSIENT_RE.match?(e.message.to_s)
        @bus&.publish("rule_loop:fix_error", rule: @rule.id, file: path, error: e.message[0, 120])
        return nil
      end
      nil
    end

    # Architecture #9: generate CANDIDATE_COUNT fixes, rescan each, apply lowest-violation winner.
    def genetic_fix(violation, src, path)
      ext    = File.extname(path).downcase
      prompt = build_prompt(violation, src, path)
      candidates = CANDIDATE_COUNT.times.filter_map do |attempt|
        sleep RATE_LIMIT_SLEEP if attempt.positive?
        code = extract_code(@agent.ask(prompt).to_s, ext)
        code if code && code.strip != src.strip
      rescue StandardError => e
        next if Master::Loop::Constants::TRANSIENT_RE.match?(e.message.to_s)
        @bus&.publish("rule_loop:fix_error", rule: @rule.id, file: path, error: e.message[0, 120])
        nil
      end
      best_candidate(candidates, path)
    end

    def best_candidate(candidates, path)
      return nil if candidates.empty?
      return candidates.first if candidates.size == 1
      scored = candidates.filter_map { |c| [rescan_candidate(c, path), c] }
      scored.empty? ? candidates.first : scored.min_by(&:first).last
    rescue StandardError
      candidates.first
    end

    def rescan_candidate(candidate, path)
      Tempfile.open(["rl_score", File.extname(path)]) do |f|
        f.write(candidate); f.flush
        result = @scanner.scan(f.path, rules: [@rule])
        result.ok? ? result.value!.size : 99
      end
    rescue StandardError
      99
    end

    def apply(path, new_src)
      write_atomic(path, new_src, encoding: "UTF-8")
      @bus&.publish("rule_loop:fix_applied", rule: @rule.id, file: path)
      true
    rescue StandardError => e
      @bus&.publish("rule_loop:write_error", rule: @rule.id, file: path, error: e.message)
      false
    end

    def build_prompt(violation, src, path)
      lang     = Master::Judge::Scan::Rule::EXT_LANG.fetch(File.extname(path).downcase, "text")
      fix_hint = violation[:fix].to_s.strip
      <<~PROMPT
        #{preamble}

        File: #{File.basename(path)} (#{lang})
        Rule violated: #{violation[:rule]}
        Line #{violation[:line]}: #{violation[:message]}
        #{fix_hint.empty? ? "" : "How to fix: #{fix_hint}"}

        Return ONLY the corrected file. If unsafe to autofix, return exactly: UNCHANGED

        ```#{lang}
        #{src}
        ```
      PROMPT
    end

    def build_diff_prompt(violation, src, path)
      lang     = Master::Judge::Scan::Rule::EXT_LANG.fetch(File.extname(path).downcase, "text")
      fix_hint = violation[:fix].to_s.strip
      <<~PROMPT
        #{preamble}

        File: #{File.basename(path)} (#{lang})
        Rule violated: #{violation[:rule]}
        Line #{violation[:line]}: #{violation[:message]}
        #{fix_hint.empty? ? "" : "How to fix: #{fix_hint}"}

        Return a unified diff patch only (like `diff -u`). Fix only the violation.
        If unsafe to autofix, return exactly: UNCHANGED

        ```#{lang}
        #{src}
        ```
      PROMPT
    end

    def preamble
      @preamble ||= @injected_preamble || begin
        soul   = Master.load_yaml(File.join(Master::ROOT, "data", "soul.yml"))
        abs    = soul.fetch("absolute", {})
        golden = abs["golden_rule"] || "PRESERVE_THEN_IMPROVE_NEVER_BREAK"
        lines  = ["Golden rule: #{golden}",
                  "Minimum change that eliminates the violation. Do not touch unrelated code."]
        abs.fetch("code_rules", {}).each { |k, v| lines << "- #{k}: #{v}" }
        abs.fetch("aesthetic_rules", {}).each { |k, v| lines << "- #{k}: #{v}" }
        lines.join("\n")
      rescue StandardError
        "Golden rule: PRESERVE_THEN_IMPROVE_NEVER_BREAK"
      end
    end

    # Architecture #10: record fix quality in learnings store.
    def record_outcomes(files, outcome)
      return unless @learnings
      ext = files.filter_map { |f| File.extname(f).downcase.delete(".").presence }.tally.max_by { |_, n| n }&.first || "unknown"
      @learnings.record(rule: @rule.id, file_type: ext, outcome:)
    rescue StandardError => e
      Master::Ground::Swallow.log(e, context: "rule_loop.record_outcomes", event_bus: @bus, rule: @rule.id)
    end
  end
  end
end
