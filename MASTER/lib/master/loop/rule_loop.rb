# frozen_string_literal: true

require "tempfile"
require_relative "../reach/atomic_write"
require_relative "constants"

module Master
  module Loop
  # Runs a single rule to convergence on a set of files.
  # Called by SuperLoop — one RuleLoop instance per rule per pass.
  class RuleLoop
    MAX_CYCLES          = 8
    # < 5% improvement = converged
    CONVERGE_THRESHOLD  = 0.05
    RATE_LIMIT_SLEEP    = 10
    MAX_FIX_RETRIES     = 2

    SEVERITY_RANK = Master::SEVERITY_RANK
    MIN_SEVERITY  = SEVERITY_RANK[:warning]

    include Master::Reach::AtomicWrite

    def initialize(rule:, agent:, scanner:, root:, bus: nil, git: nil)
      @rule    = rule
      @agent   = agent
      @scanner = scanner
      @root    = root
      @bus     = bus
      @git     = git
    end

    def injected_preamble=(text)
      @injected_preamble = text
    end

    # Returns { fixed:, cycles:, status: :clean | :converged | :max_cycles }
    def run(files, max_cycles: MAX_CYCLES)
      prev_count  = nil
      total_fixed = 0

      max_cycles.times do |i|
        violations = scan_files(files)

        if violations.empty?
          @bus&.publish("rule_loop:clean", rule: @rule.id, cycles: i + 1)
          return { fixed: total_fixed, cycles: i + 1, status: :clean }
        end

        if converged?(prev_count, violations.size)
          @bus&.publish("rule_loop:converged", rule: @rule.id, cycles: i + 1, remaining: violations.size)
          return { fixed: total_fixed, cycles: i + 1, status: :converged }
        end

        prev_count = violations.size
        fixed      = fix_batch(violations)
        total_fixed += fixed
        @bus&.publish("rule_loop:cycle", rule: @rule.id, cycle: i + 1, violations: violations.size, fixed:)
      end

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
        new_src = request_fix(v)
        next unless new_src
        apply(v[:file], new_src) && (fixed += 1)
      end
      fixed
    end

    def request_fix(violation)
      path = violation[:file]
      return unless File.exist?(path)
      src = File.read(path, encoding: "UTF-8")
      prompt = build_prompt(violation, src, path)
      MAX_FIX_RETRIES.times do |attempt|
        sleep RATE_LIMIT_SLEEP * attempt if attempt.positive?
        response = @agent.ask(prompt).to_s
        code     = extract(response, File.extname(path).downcase)
        return code if code && code.strip != src.strip
      rescue StandardError => e
        next if Master::Loop::TRANSIENT_RE.match?(e.message.to_s)
        @bus&.publish("rule_loop:fix_error", rule: @rule.id, file: path, error: e.message[0, 120])
        return nil
      end
      nil
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

    def extract(text, ext)
      return nil if text.strip == "UNCHANGED"
      return nil if text.match?(/\b(?:error|exception|rate.?limit|i cannot|as an ai)\b/i)
      lang = Master::Judge::Scan::Rule::EXT_LANG.fetch(ext, "text")
      langs_re = Regexp.union(lang, "text", "")
      if (m = text.match(/```(?:#{langs_re})?\n(.*?)```/m))
        return m[1].strip
      end
      text.strip.empty? ? nil : text.strip
    end

    def preamble
      @preamble ||= @injected_preamble || begin
        soul  = Master.load_yaml(File.join(Master::ROOT, "data", "soul.yml"))
        golden = soul.dig("absolute", "golden_rule") || "PRESERVE_THEN_IMPROVE_NEVER_BREAK"
        "Golden rule: #{golden}\nMinimum change that eliminates the violation. Do not touch unrelated code."
      rescue StandardError => _e
        "Golden rule: PRESERVE_THEN_IMPROVE_NEVER_BREAK"
      end
    end

    def converged?(prev, current)
      return false unless prev
      improvement = (prev - current).to_f / [prev, 1].max
      improvement < CONVERGE_THRESHOLD
    end
  end
  end
end
