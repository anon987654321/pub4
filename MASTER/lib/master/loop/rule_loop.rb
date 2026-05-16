# frozen_string_literal: true

require "tempfile"
require_relative "../reach/atomic_write"
require_relative "constants"
require_relative "fix_helpers"
require_relative "patch_applier"

module Master
  module Loop
  # Runs a single rule to convergence on a set of files.
  # Called by SuperLoop — one RuleLoop instance per rule per pass.
  class RuleLoop
    MAX_CYCLES       = 8
    RATE_LIMIT_SLEEP = 10
    MAX_FIX_RETRIES  = 2
    # Architecture #9: generate N candidates, score by rescan, apply winner.
    CANDIDATE_COUNT  = 3

    SEVERITY_RANK = Master::SEVERITY_RANK
    MIN_SEVERITY  = SEVERITY_RANK[:warning]

    include Master::Reach::AtomicWrite
    include Master::Loop::FixHelpers

    def initialize(rule:, agent:, scanner:, root:, bus: nil, git: nil, learnings: nil)
      @rule      = rule
      @agent     = agent
      @scanner   = scanner
      @root      = root
      @bus       = bus
      @git       = git
      @learnings = learnings
    end

    def injected_preamble=(text)
      @injected_preamble = text
    end

    # Returns { fixed:, cycles:, status: :clean | :converged | :max_cycles }
    def run(files, max_cycles: MAX_CYCLES)
      ast_pre_pass(files)
      prev_count  = nil
      total_fixed = 0

      max_cycles.times do |i|
        violations = scan_files(files)

        if violations.empty?
          record_outcomes(files, :fixed) if i.positive?
          @bus&.publish("rule_loop:clean", rule: @rule.id, cycles: i + 1)
          return { fixed: total_fixed, cycles: i + 1, status: :clean }
        end

        if converged?(prev_count, violations.size)
          record_outcomes(files, :stuck)
          @bus&.publish("rule_loop:converged", rule: @rule.id, cycles: i + 1, remaining: violations.size)
          return { fixed: total_fixed, cycles: i + 1, status: :converged }
        end

        prev_count = violations.size
        fixed      = fix_batch(violations)
        total_fixed += fixed
        @bus&.publish("rule_loop:cycle", rule: @rule.id, cycle: i + 1, violations: violations.size, fixed:)
      end

      record_outcomes(files, :stuck)
      { fixed: total_fixed, cycles: MAX_CYCLES, status: :max_cycles }
    rescue StandardError => e
      @bus&.publish("rule_loop:error", rule: @rule.id, error: e.message)
      { fixed: 0, cycles: 0, status: :error }
    end

    private

    def scan_files(files)
      files.flat_map do |path|
        next [] unless File.exist?(path)
        result = @scanner.scan(path, rules: [@rule])
        next [] unless result.ok?
        ext = File.extname(path).downcase
        result.value!
              .select  { |f| (SEVERITY_RANK[f[:severity]] || 0) >= MIN_SEVERITY }
              .map     { |f| f.merge(file: path, ext:) }
      end
    end

    def fix_batch(violations)
      by_file = violations.uniq { |v| v[:file] }
      fixed   = 0
      by_file.each do |v|
        # Architecture #6: severity:error routes through council deliberation.
        new_src = v[:severity].to_sym == :error ? council_fix(v) : request_fix(v)
        next unless new_src
        apply(v[:file], new_src) && (fixed += 1)
      end
      fixed
    end

    def council_fix(violation)
      path = violation[:file]
      return unless File.exist?(path)
      src  = File.read(path, encoding: "UTF-8")
      prompt = <<~PROMPT
        #{preamble}

        File: #{File.basename(path)}
        Rule violated (severity: ERROR): #{violation[:rule]}
        Line #{violation[:line]}: #{violation[:message]}
        #{violation[:fix].to_s.empty? ? "" : "Suggested fix: #{violation[:fix]}"}

        Three reviewers assess this violation before any fix is applied:

        As Skeptic: Is this violation real, or a false positive? What is the blast radius of a fix?
        As Security reviewer: Does this violation create an attack surface? What must the fix preserve?
        As Maintainer: What is the minimum change that eliminates the violation without drift?

        After reviewing all three perspectives, produce the corrected file.
        Only apply if all three perspectives agree a fix is safe.
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

    # Architecture #5 + #9: diff mode for large files; genetic candidates for small files.
    def request_fix(violation)
      path = violation[:file]
      return unless File.exist?(path)
      src = File.read(path, encoding: "UTF-8")
      return diff_fix(violation, src, path) if src.bytesize > PatchApplier::DIFF_THRESHOLD
      genetic_fix(violation, src, path)
    end

    # Architecture #5: request unified diff patch; apply with PatchApplier.
    def diff_fix(violation, src, path)
      ext    = File.extname(path).downcase
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

    # Architecture #9: generate CANDIDATE_COUNT fixes, rescan each, apply best.
    def genetic_fix(violation, src, path)
      ext    = File.extname(path).downcase
      prompt = build_prompt(violation, src, path)
      candidates = CANDIDATE_COUNT.times.filter_map do |attempt|
        sleep RATE_LIMIT_SLEEP if attempt.positive?
        response = @agent.ask(prompt).to_s
        code = extract_code(response, ext)
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
      scored = candidates.filter_map do |c|
        violations = rescan_candidate(c, path)
        [violations, c]
      end
      scored.empty? ? candidates.first : scored.min_by { |count, _| count }.last
    rescue StandardError
      candidates.first
    end

    def rescan_candidate(candidate, path)
      Tempfile.open(["rl_score", File.extname(path)]) do |f|
        f.write(candidate)
        f.flush
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
      lang = Master::Judge::Scan::Rule::EXT_LANG.fetch(File.extname(path).downcase, "text")
      fix_hint = violation[:fix].to_s.strip
      <<~PROMPT
        #{preamble}

        File: #{File.basename(path)} (#{lang})
        Rule violated: #{violation[:rule]}
        Line #{violation[:line]}: #{violation[:message]}
        #{fix_hint.empty? ? "" : "How to fix: #{fix_hint}"}

        Return ONLY the corrected file. If this cannot be safely autofixed, return exactly: UNCHANGED

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

        Return a unified diff patch only (like `diff -u` output). Do NOT return the whole file.
        Fix only the violation. If unsafe to autofix, return exactly: UNCHANGED

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
      rescue StandardError => _e
        "Golden rule: PRESERVE_THEN_IMPROVE_NEVER_BREAK"
      end
    end

    # Architecture #4: run AST mechanical fixes before LLM scan cycle.
    def ast_pre_pass(files)
      files.each do |path|
        next unless File.exist?(path)
        src = File.read(path, encoding: "UTF-8")
        result = Judge::Scan::AstFixer.fix(path, src)
        if result.changed
          @bus&.publish("rule_loop:ast_fixed", rule: @rule.id, file: path, transforms: result.transforms)
        end
      rescue StandardError => e
        @bus&.publish("rule_loop:ast_error", file: path, error: e.message)
      end
    end

    # Architecture #10: record fix quality in SQLite learnings store.
    def record_outcomes(files, outcome)
      return unless @learnings
      ext = files.filter_map { |f| File.extname(f).downcase.delete(".").then { |e| e.empty? ? nil : e } }
                 .tally.max_by { |_, n| n }&.first || "unknown"
      @learnings.record(rule: @rule.id, file_type: ext, outcome: outcome)
    rescue StandardError
      nil
    end
  end
  end
end
