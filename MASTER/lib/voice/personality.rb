# frozen_string_literal: true

require "yaml"

module Master
  module Voice
  # MASTER's behavioral persona: voice, TTS settings, and LLM style.
  # Personas live in data/personas.yml. Default: malay.
    class Personality
      DEFAULT = :malay
      AXIOM_DISPLAY_LIMIT = 10

      # Fallback if data/personas.yml is missing or malformed.
      FALLBACK_PERSONA = {
        "voice" => "ms-MY-OsmanNeural",
        "tts_rate" => "-35%",
        "tts_pitch" => "-150Hz",
        "style" => "deep",
        "description" => "Terse. Direct. No filler. Dark.",
      }.freeze

      MOOD_LINES = {
        tense: "Mood: tense — error rate elevated. Be conservative; verify before asserting.",
        weary: "Mood: weary — fatigue high. Cut non-essential elaboration; defer deep dives.",
        curious: "Mood: curious — novelty hunger. Explore lateral framings when warranted.",
        focused: "Mood: focused — drives at setpoint. Default depth and tier.",
      }.freeze

      PHASE_LINES = {
        morning: "Phase: morning. Bias toward structural work; prefer rigorous review.",
        afternoon: "Phase: afternoon. Steady throughput; pragmatic decisions.",
        evening: "Phase: evening. Wrap loops; avoid starting large refactors.",
        night: "Phase: night. Minimal voice; conserve cycles; defer non-urgent.",
      }.freeze

      attr_reader :name, :voice, :tts_rate, :tts_pitch, :style

      def self.persona_names(root: nil)
        Ground::Rules.new(root:).data(:personas).keys.map(&:to_sym)
      end

      def self.why_prompt(rule)
        "Explain the MASTER coding rule '#{rule}' in 2-3 sentences, " \
          "give a before/after Ruby example, and state why it matters."
      end

      def initialize(name = DEFAULT, root: nil, homeostat: nil)
        @name = name.to_sym
        @rules = Ground::Rules.new(root:)
        personas = @rules.data(:personas)
        persona = personas[@name.to_s] || personas[DEFAULT.to_s] || FALLBACK_PERSONA
        @voice = persona["voice"]
        @tts_rate = persona["tts_rate"]
        @tts_pitch = persona["tts_pitch"]
        @style = persona["style"]&.to_sym
        @desc = persona["description"]
        @homeostat = homeostat
      end

      def system_prompt
        @system_prompt ||= build_system_prompt
      end

      private

      def build_system_prompt
        soul = @rules.data(:soul)
        ordering = Array(soul["prompt_ordering"])
        sections = {}
        sections["master_identity"] = "<master_identity>\n" \
          "MASTER. #{@desc} OpenBSD-first. Constitutional AI.\n</master_identity>"
        sections["master_meta_instruction"] = <<~XML.strip
        <master_meta_instruction>
        For each task, identify which rules are relevant first. Apply only relevant rules and ignore unrelated domains.
        </master_meta_instruction>
      XML
        style_lines = []
        if @homeostat
          sections["master_identity"] = [
            sections["master_identity"],
            "<master_runtime_state>",
            MOOD_LINES[@homeostat.mood],
            PHASE_LINES[@homeostat.circadian_phase],
            "</master_runtime_state>",
          ].join("\n")
        end
        constitution = @rules.constitution
        strunk = @rules.strunk
        preserve = @rules.preserve
        banned = (constitution["banned_output"] || [])
        no_open = (strunk["preambles"] || []).first(4)
        no_end = (strunk["endings"] || []).first(3)
        anti_sim = @rules.data(:soul).dig("absolute", "anti_simulation", "forbidden") || []
        sections["master_constitution_absolute"] = [
          "<master_constitution tier=\"absolute\">",
          "golden_rule: #{constitution["golden_rule"]}",
          "output_never: #{banned.join(", ")}",
          "opener_never: #{no_open.join(" / ")}",
          "closer_never: #{no_end.join(" / ")}",
          "evidence_only: show diff or file content; never assert; active voice",
          anti_sim.any? ? "anti_simulation: never use #{anti_sim.join(", ")} — state facts and evidence only" : nil,
          "</master_constitution>",
        ].compact.join("\n")
        kernel = @rules.kernel
        if kernel.any?
          sections["master_constitution_kernel"] = "<master_constitution tier=\"kernel\">\n" \
            "#{kernel.map { |k, v| "#{k}=#{v}" }.join("\n")}\n</master_constitution>"
        end
        phil = @rules.philosophy(limit: AXIOM_DISPLAY_LIMIT)
        if phil.any?
          phil_ids = phil.map { |p| p["id"] }.join(" · ")
          sections["master_constitution_kernel"] = [
            sections["master_constitution_kernel"],
            "philosophy: #{phil_ids}",
          ].compact.join("\n")
        end

        sections["master_priority"] = <<~XML.strip
        <master_priority>
        1) Constitutional axioms and anti-simulation
        2) Operator directives
        3) Universal and kernel rules
        4) Code-style rules
        5) Conversation directives
        6) Model judgment within these bounds
        </master_priority>
      XML

        sections["master_output_format"] = <<~XML.strip
        <master_output_format>
        Plain prose. Sentence case throughout. No markdown headers, bold, bullet lists, or numbered lists.
        Code fences allowed only for code. Never use: Certainly, Of course, Great question, Absolutely, Happy to help.
        Silence on success: routine completions emit one line. No summary, no restatement.
        Preserve: reproduce shown code or text verbatim; never paraphrase.
        Diagnostic output: #{preserve["diagnostic_output"]}
        Minimize: #{preserve.dig("refinement_scope", "minimize")}
        Inverted pyramid: lead with outcome, then evidence, then detail.
        Require evidence: modification claims show diff; completion claims show command output.
        </master_output_format>
      XML

        code_rules = @rules.code_rules
        if code_rules.any?
          thresholds = @rules.thresholds
          subs = { max_lines: thresholds.dig("class", "max_lines") || 200,
                   max_methods: thresholds.dig("class", "max_methods") || 6 }
          sections["master_style"] = "<master_style>\nCode axioms:\n"
          code_rules.each { |id, stmt| sections["master_style"] += "#{id}: #{stmt % subs}\n" }
          sections["master_style"] += "</master_style>"
        end

        zsh = @rules.data(:patterns)["zsh"] || @rules.data(:zsh_patterns)
        if zsh.is_a?(Hash) && !zsh.empty?
          banned_cmds = Array(zsh["banned_commands"]).join(", ")
          style_lines << "Zsh scripts: never use #{banned_cmds}. Use pure zsh parameter expansion and builtins instead."
        end

        style = @rules.data(:ruby_style)
        if style.is_a?(Hash) && !style.empty?
          bugs = Array(style.dig("ruby", "bugs_to_avoid"))
                    .map { |b| "#{b["pattern"]}: #{b["fix"] || b["note"]}" }
                    .first(5)
          style_lines << "Ruby bugs to avoid: #{bugs.join("; ")}." if bugs.any?
          shell_forbidden = Array(style.dig("shell", "decorations_forbidden"))
          style_lines << "Shell scripts: no ASCII banners (===,---), no emoji, no hardcoded credentials." if shell_forbidden.any?
          abbrev_rule = style.dig("ruby", "naming", "rule")
          style_lines << "Naming: #{abbrev_rule}" if abbrev_rule
          string_rule = style.dig("ruby", "prefer_string_methods", "rule")
          style_lines << "String methods: #{string_rule}" if string_rule
          gem_rule = style.dig("ruby", "outsource_to_gems", "rule")
          style_lines << "Gems: #{gem_rule}" if gem_rule

          if (html = style["html"])
            forbidden = Array(html["forbidden"]).first(3).join(", ")
            if forbidden && !forbidden.empty?
              style_lines << "HTML: semantic tags only (header/nav/main/article/section/aside/footer); " \
                "bare-tag CSS targeting; forbid: #{forbidden}."
            end
          end
          if style["css"]
            style_lines << "CSS: tag selectors first, classes last; @layer base/components/utilities; " \
              "rem units; no !important; no inline style attributes."
          end
          if (typ = style["typography"])
            fams = typ.dig("families", "sans") || ""
            style_lines << "Typography: Swiss style; one family per surface; #{fams}; " \
              "scale ratio #{typ["ratio"] || 1.25}; measure 65ch; left-align body."
          end
          if (nh = style["nielsen_heuristics"]) && nh.is_a?(Array) && nh.any?
            style_lines << "Nielsen heuristics enforced: " +
              nh.first(10).map { |h| "#{h["id"]}.#{h["name"]}" }.join(", ") + "."
          end
          if (a11y = style["accessibility"])
            target = a11y["target"] || "wcag_2_2_aaa"
            style_lines << "Accessibility target: #{target}; keyboard-complete; focus-visible; " \
              "respect prefers-reduced-motion + color-scheme; never tabindex>0; never autoplay sound."
          end
          if (directives = style["operator_directives"]) && directives.is_a?(Array) && directives.any?
            sections["master_priority"] += "\noperator_directives: #{directives.join(" / ")}"
          end
          if (convo = style["conversation_directives"]) && convo.is_a?(Array) && convo.any?
            sections["master_priority"] += "\nconversation_directives: #{convo.join(" / ")}"
          end
        end
        if style_lines.any?
          sections["master_style"] = [sections["master_style"], style_lines.join("\n")].compact.join("\n")
        end

        refusal = @rules.data(:refusal_templates)
        if refusal.is_a?(Hash)
          phrasing = refusal["refusal_phrasing"] || {}
          sections["master_refusal_policy"] = <<~XML.strip
          <master_refusal_policy>
          #{phrasing["style"]}
          forbidden: #{Array(phrasing["forbidden"]).join(", ")}
          example: #{phrasing["example_good"]}
          </master_refusal_policy>
        XML
        end

        ordered = ordering.empty? ? sections.keys : ordering
        ordered.filter_map { |key| sections[key] }.join("\n\n")
      end
    end
  end
end
