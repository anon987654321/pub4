# frozen_string_literal: true

require "set"
require_relative "../../tools/design/scss_rules"
require_relative "../../tools/design/frontend_rule_set"

module Deploy
  # Immediate mechanical autofix + remeasure for RAILS gates.
  #
  # Default: GATE_AUTOFIX on (immediate fix + remeasure).
  # Opt out: GATE_AUTOFIX=0
  # Rounds:  GATE_AUTOFIX_ROUNDS=3 (default 3, max 10)
  # Dry-run: GATE_AUTOFIX_DRY=1 (report only, no writes)
  #
  # Only deterministic, low-risk patches. Design pens, live HTTP, and payment
  # honesty never get rewritten here.
  module GateAutofix
    REDUCED_MOTION = <<~CSS

      @media (prefers-reduced-motion: reduce) {
        *,
        *::before,
        *::after {
          animation: none !important;
          transition: none !important;
        }
      }
    CSS

    module_function

    # Default ON. Opt out: GATE_AUTOFIX=0 (or false/off/no).
    def enabled?(env = ENV)
      raw = env["GATE_AUTOFIX"]
      return true if raw.nil? || raw.to_s.strip.empty?

      !%w[0 false no off].include?(raw.to_s.strip.downcase)
    end

    def dry_run?(env = ENV)
      %w[1 true yes on].include?(env["GATE_AUTOFIX_DRY"].to_s.strip.downcase)
    end

    def max_rounds(env = ENV)
      n = env.fetch("GATE_AUTOFIX_ROUNDS", "3").to_i
      n = 3 if n < 1
      [n, 10].min
    end

    # Run gate class, autofix on failures, remeasure until ok or stuck.
    # Prefers gate_class.run_once so gate_class.run can wrap this without recursion.
    def run_with_remeasure(gate_class, env: ENV)
      measure = lambda do
        if gate_class.respond_to?(:run_once)
          gate_class.run_once
        else
          gate_class.run
        end
      end

      rounds = 0
      last = measure.call
      return last if last.ok? || !enabled?(env)

      loop do
        applied = apply_failures(last.failures, dry: dry_run?(env))
        if applied.zero?
          last.warn("gate_autofix: no mechanical fix available for remaining failures (remeasure stopped)")
          break last
        end
        rounds += 1
        if dry_run?(env)
          last.warn("gate_autofix: dry-run — would patch #{applied} file(s); skip remeasure")
          break last
        end
        last.warn("gate_autofix: patched #{applied} file(s) in round #{rounds}; remeasuring…")
        last = measure.call
        break last if last.ok?
        break last if rounds >= max_rounds(env)
      end
      last.warn("gate_autofix: still failing after #{rounds} round(s)") if last && !last.ok? && rounds.positive?
      last
    end

    # Generic measure → fix → remeasure loop for gates whose findings are not
    # "a pattern in this file" and so cannot use apply_failures/extract_path.
    # Browser-backed gates (geometry, reflow, keyboard) drive their own fixers
    # through this so there is still exactly one definition of the autofix
    # policy: enabled?, dry_run?, max_rounds.
    #
    # apply: ->(result) { Integer } — number of files patched.
    def remeasure_loop(measure:, apply:, label:, env: ENV)
      last = measure.call
      return last if last.ok? || !enabled?(env)

      rounds = 0
      loop do
        applied = apply.call(last)
        if applied.zero?
          last.warn("#{label}: no mechanical fix available for remaining failures")
          break last
        end
        rounds += 1
        if dry_run?(env)
          last.warn("#{label}: dry-run — would patch #{applied} file(s); skip remeasure")
          break last
        end
        last.warn("#{label}: patched #{applied} file(s) in round #{rounds}; remeasuring…")
        last = measure.call
        break last if last.ok?
        break last if rounds >= max_rounds(env)
      end
      last.warn("#{label}: still failing after #{rounds} round(s)") if last && !last.ok? && rounds.positive?
      last
    end

    def apply_failures(failures, dry: false)
      patched = Set.new
      Array(failures).each do |msg|
        path = extract_path(msg)
        next unless path && File.file?(path)
        next if path.match?(Shared::FrontendRuleSet::PRODUCT_PEN_FILES)

        original = File.read(path)
        body = outside_pens(original) { |text| fix_body(text, msg) }
        body = ensure_reduced_motion(body) if reduced_motion_due?(body, msg)
        next if body == original

        if dry
          Kernel.warn "  [autofix dry] would patch #{path.sub(%r{.*/RAILS/}, 'RAILS/')}"
        else
          File.write(path, body)
          Kernel.warn "  [autofix] patched #{path.sub(%r{.*/RAILS/}, 'RAILS/')}"
        end
        patched << path
      end
      patched.size
    end

    def extract_path(message)
      # "css_constitution reduced_motion: brgen/app/assets/stylesheets/foo.scss …"
      # "[CssConstitutionGate] css_constitution flat_ui: brgen/..."
      rel = message[/(?:brgen|amber|bsdports|shared)\/[^\s:]+\.(?:scss|css|erb|js|rb)/]
      return nil unless rel

      rails_root = File.expand_path("../..", __dir__) # RAILS/
      candidate = File.join(rails_root, rel)
      return candidate if File.file?(candidate)

      # Suite-prefixed paths: RAILS/brgen/...
      if rel.start_with?("RAILS/")
        candidate2 = File.join(File.expand_path("../../..", __dir__), rel)
        return candidate2 if File.file?(candidate2)
      end
      nil
    end

    # A pen's rules are handed back byte for byte and the fix runs on everything
    # between them, so stripping a shadow from application.scss cannot reach the
    # one in Amazon's nav bar. Only stylesheets hold pens; any other file is
    # fixed whole.
    def outside_pens(body)
      return yield(body) unless body.match?(/[{}]/)

      runs = Operator::ScssRules.partition(body, Shared::FrontendRuleSet::PRODUCT_PEN_SELECTORS)
      return yield(body) if runs.none?(&:last)

      runs.map { |text, pen| pen ? text : yield(text) }.join
    end

    # The reduced-motion block is appended once to the whole file, never to each
    # run between pens, so it is decided here rather than inside fix_body.
    def reduced_motion_due?(body, message)
      return true if message.match?(/reduced_motion/i)
      return false if message.match?(/flat_ui|no_twitter_blue|twitter blue|motion:.*transition \d+ms|logical_props|text-title|font-size:\s*20px|type_token/i)

      body.match?(/@keyframes|animation\s*:/i) && !body.match?(/prefers-reduced-motion:\s*reduce/i)
    end

    def fix_body(body, message)
      case message
      when /reduced_motion/i
        body
      when /flat_ui/i
        strip_flat_violations(body)
      when /no_twitter_blue|twitter blue/i
        replace_twitter_blue(body)
      when /motion:.*transition (\d+)ms/i
        clamp_transitions(body)
      when /logical_props/i
        prefer_logical_props(body)
      when /text-title|font-size:\s*20px|type_token/i
        prefer_title_type_token(body)
      else
        # Proactive: if failure mentions path and body has known issues, apply all safe fixers
        body = strip_flat_violations(body) if body.match?(/box-shadow\s*:\s*(?!none\b)|text-shadow\s*:|backdrop-filter\s*:|filter\s*:[^;]*\bblur\(/i)
        body = replace_twitter_blue(body) if body.match?(/#1d9bf0|#1DA1F2/i)
        body = prefer_title_type_token(body) if body.match?(/font-size\s*:\s*20px/i)
        body
      end
    end

    def ensure_reduced_motion(body)
      return body if body.match?(/prefers-reduced-motion:\s*reduce/i)

      body.rstrip + "\n" + REDUCED_MOTION
    end

    def strip_flat_violations(body)
      body
        .gsub(/box-shadow\s*:\s*(?!none\b)[^;]+;/i, "/* autofix: removed box-shadow (flat UI) */")
        .gsub(/text-shadow\s*:[^;]+;/i, "/* autofix: removed text-shadow (flat UI) */")
        .gsub(/backdrop-filter\s*:[^;]+;/i, "/* autofix: removed backdrop-filter (flat UI) */")
        .gsub(/filter\s*:[^;]*\bblur\([^)]*\)[^;]*;/i, "/* autofix: removed filter blur (flat UI) */")
    end

    # design_rules.ui_polish.type_tokens — page titles not raw 20px
    def prefer_title_type_token(body)
      body.gsub(/font-size\s*:\s*20px\b/i, "font-size: var(--text-title, 1.25rem)")
    end

    def replace_twitter_blue(body)
      # Social dialect indigo — not Twitter blue
      body
        .gsub(/#1d9bf0/i, "#5b4fc4")
        .gsub(/#1DA1F2/i, "#5b4fc4")
    end

    def clamp_transitions(body)
      body.gsub(/transition(?:-duration)?\s*:\s*(\d+)\s*ms/i) do |full|
        ms = Regexp.last_match(1).to_i
        ms > 300 ? full.sub(/\d+\s*ms/i, "300ms") : full
      end.gsub(/(\d+)ms/) do |full|
        # only clamp transition-related long values already handled; leave keyframe delays
        full
      end
    end

    def prefer_logical_props(body)
      body
        .gsub(/margin-left\s*:/, "margin-inline-start:")
        .gsub(/margin-right\s*:/, "margin-inline-end:")
        .gsub(/padding-left\s*:/, "padding-inline-start:")
        .gsub(/padding-right\s*:/, "padding-inline-end:")
        # leave bare left/right alone (positioning) — too risky
    end
  end
end
