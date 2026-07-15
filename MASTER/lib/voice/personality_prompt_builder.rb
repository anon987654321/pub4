# frozen_string_literal: true

module Master
  module Voice
    # Builds Personality's system prompt from small, independently readable sections.
    module PersonalityPromptBuilder
      private

      def build_system_prompt
        soul = @rules.data(:soul)
        sections = base_prompt_sections
        add_runtime_state(sections)
        add_constitution(sections, soul)
        add_priority(sections)
        add_output_format(sections)
        add_code_rules(sections)
        add_language_style(sections)
        add_disclaimer(sections)
        add_refusal_policy(sections)
        ordered_sections(sections, soul)
      end

      def base_prompt_sections
        {
          "master_identity" => [
            "<master_identity>",
            "MASTER. #{@desc} OpenBSD-first. Constitutional AI.",
            persona_knowledge_sources,
            load_identity,
            "</master_identity>",
          ].compact.join("\n"),
          "master_meta_instruction" => meta_instruction,
        }
      end

      def meta_instruction
        <<~XML.strip
          <master_meta_instruction>
          For each task, identify which rules are relevant first. Apply only relevant rules and ignore unrelated domains.
          </master_meta_instruction>
        XML
      end

      def add_runtime_state(sections)
        return unless @homeostat

        sections["master_identity"] = [
          sections["master_identity"],
          "<master_runtime_state>",
          Personality::MOOD_LINES[@homeostat.mood],
          Personality::PHASE_LINES[@homeostat.circadian_phase],
          "</master_runtime_state>",
        ].join("\n")
      end

      def add_constitution(sections, soul)
        sections["master_constitution_absolute"] = absolute_constitution(soul)
        kernel = kernel_constitution
        philosophy = philosophy_line
        sections["master_constitution_kernel"] = [kernel, philosophy].compact.join("\n")
      end

      def absolute_constitution(soul)
        constitution = @rules.constitution
        strunk = @rules.strunk
        anti_simulation = soul.dig("absolute", "anti_simulation", "forbidden") || []
        [
          "<master_constitution tier=\"absolute\">",
          "golden_rule: #{constitution["golden_rule"]}",
          "output_never: #{Array(constitution["banned_output"]).join(', ')}",
          "opener_never: #{Array(strunk["preambles"]).first(4).join(' / ')}",
          "closer_never: #{Array(strunk["endings"]).first(3).join(' / ')}",
          "evidence_only: show diff or file content; never assert; active voice",
          anti_simulation_line(anti_simulation),
          "</master_constitution>",
        ].compact.join("\n")
      end

      def anti_simulation_line(forbidden)
        return if forbidden.empty?

        "anti_simulation: never use #{forbidden.join(', ')} — state facts and evidence only"
      end

      def kernel_constitution
        kernel = @rules.kernel
        return if kernel.empty?

        body = kernel.map { |key, value| "#{key}=#{value}" }.join("\n")
        "<master_constitution tier=\"kernel\">\n#{body}\n</master_constitution>"
      end

      def philosophy_line
        philosophy = @rules.philosophy(limit: Personality::AXIOM_DISPLAY_LIMIT)
        return if philosophy.empty?

        "philosophy: #{philosophy.map { |item| item["id"] }.join(' · ')}"
      end

      def add_priority(sections)
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
      end

      def add_output_format(sections)
        preserve = @rules.preserve
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
      end

      def add_code_rules(sections)
        rules = @rules.code_rules
        return if rules.empty?

        thresholds = @rules.thresholds
        substitutions = {
          max_lines: thresholds.dig("class", "max_lines") || 200,
          max_methods: thresholds.dig("class", "max_methods") || 6,
        }
        body = rules.map { |id, statement| "#{id}: #{statement % substitutions}" }.join("\n")
        sections["master_style"] = "<master_style>\nCode axioms:\n#{body}\n</master_style>"
      end

      def add_language_style(sections)
        lines = zsh_style_lines
        style = @rules.data(:ruby_style)
        if style.is_a?(Hash) && !style.empty?
          lines.concat(ruby_style_lines(style))
          lines.concat(web_style_lines(style))
          append_directives(sections, style)
        end
        return if lines.empty?

        sections["master_style"] = [sections["master_style"], lines.join("\n")].compact.join("\n")
      end

      def zsh_style_lines
        zsh = @rules.data(:patterns)["zsh"] || @rules.data(:zsh_patterns)
        return [] unless zsh.is_a?(Hash) && !zsh.empty?

        banned = Array(zsh["banned_commands"]).join(", ")
        ["Zsh scripts: never use #{banned}. Use pure zsh parameter expansion and builtins instead."]
      end

      def ruby_style_lines(style)
        bugs = Array(style.dig("ruby", "bugs_to_avoid")).first(5)
        bug_text = bugs.map { |item| "#{item["pattern"]}: #{item["fix"] || item["note"]}" }.join("; ")
        [
          ("Ruby bugs to avoid: #{bug_text}." unless bugs.empty?),
          shell_style_line(style),
          optional_rule("Naming", style.dig("ruby", "naming", "rule")),
          optional_rule("String methods", style.dig("ruby", "prefer_string_methods", "rule")),
          optional_rule("Gems", style.dig("ruby", "outsource_to_gems", "rule")),
        ].compact
      end

      def shell_style_line(style)
        return if Array(style.dig("shell", "decorations_forbidden")).empty?

        "Shell scripts: no ASCII banners (===,---), no emoji, no hardcoded credentials."
      end

      def optional_rule(label, rule)
        "#{label}: #{rule}" if rule
      end

      def web_style_lines(style)
        [
          html_style_line(style["html"]),
          css_style_line(style["css"]),
          typography_style_line(style["typography"]),
          heuristics_style_line(style["nielsen_heuristics"]),
          accessibility_style_line(style["accessibility"]),
        ].compact
      end

      def html_style_line(html)
        return unless html

        forbidden = Array(html["forbidden"]).first(3).join(", ")
        return if forbidden.empty?

        "HTML: semantic tags only (header/nav/main/article/section/aside/footer); bare-tag CSS targeting; " \
          "forbid: #{forbidden}."
      end

      def css_style_line(css)
        return unless css

        "CSS: tag selectors first, classes last; @layer base/components/utilities; " \
          "rem units; no !important; no inline style attributes."
      end

      def typography_style_line(typography)
        return unless typography

        families = typography.dig("families", "sans") || ""
        "Typography: Swiss style; one family per surface; #{families}; " \
          "scale ratio #{typography["ratio"] || 1.25}; measure 65ch; left-align body."
      end

      def heuristics_style_line(heuristics)
        return unless heuristics.is_a?(Array) && !heuristics.empty?

        labels = heuristics.first(10).map { |item| "#{item["id"]}.#{item["name"]}" }
        "Nielsen heuristics enforced: #{labels.join(', ')}."
      end

      def accessibility_style_line(accessibility)
        return unless accessibility

        target = accessibility["target"] || "wcag_2_2_aaa"
        "Accessibility target: #{target}; keyboard-complete; focus-visible; " \
          "respect prefers-reduced-motion + color-scheme; never tabindex>0; never autoplay sound."
      end

      def append_directives(sections, style)
        append_priority(sections, "operator_directives", style["operator_directives"])
        append_priority(sections, "conversation_directives", style["conversation_directives"])
      end

      def append_priority(sections, label, values)
        directives = Array(values).compact.map(&:to_s)
        sections["master_priority"] += "\n#{label}: #{directives.join(' / ')}" unless directives.empty?
      end

      def add_disclaimer(sections)
        if @name == :medic
          sections["master_medical_disclaimer"] = medical_disclaimer
        elsif !@disclaimer.empty?
          sections["master_special_disclaimer"] = special_disclaimer
        end
      end

      def medical_disclaimer
        text = @disclaimer.empty? ? "Not a substitute for professional medical advice." : @disclaimer
        ["<master_medical_disclaimer>", text, "Append this disclaimer to every medical response.",
         "</master_medical_disclaimer>"].join("\n")
      end

      def special_disclaimer
        ["<master_special_disclaimer>", @disclaimer, "</master_special_disclaimer>"].join("\n")
      end

      def add_refusal_policy(sections)
        refusal = @rules.data(:patterns)["refusal_templates"]
        return unless refusal.is_a?(Hash)

        phrasing = refusal["refusal_phrasing"] || {}
        sections["master_refusal_policy"] = <<~XML.strip
          <master_refusal_policy>
          #{phrasing["style"]}
          forbidden: #{Array(phrasing["forbidden"]).join(', ')}
          example: #{phrasing["example_good"]}
          </master_refusal_policy>
        XML
      end

      def ordered_sections(sections, soul)
        ordering = Array(soul["prompt_ordering"])
        ordering = sections.keys if ordering.empty?
        ordering.filter_map { |key| sections[key] }.join("\n\n")
      end
    end
  end
end
