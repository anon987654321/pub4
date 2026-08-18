# frozen_string_literal: true

module Master
  module Voice
    # Builds Personality's system prompt from small, independently readable sections.
    module PersonalityPromptBuilder
      # Every persona (lawyer, medic, trader, architect...) got the same
      # unconditional block of Ruby/CSS/HTML/Nielsen/accessibility code-style
      # rules stapled onto its prompt regardless of domain -- pure token
      # bloat on a "not legal advice" or "not medical advice" turn, and
      # attention-diluting noise besides. CORE_SECTIONS is what every prompt
      # needs regardless of task (identity, constitution, output contract,
      # refusal policy); CONTEXTUAL_SECTIONS is code/design style, only
      # actually load-bearing when the turn is about code. Default
      # (context: :full) is byte-for-byte what every prompt produced before
      # this split -- :core is strictly additive, opt-in, currently unused
      # by the sole call site (Personality is built once at boot, before any
      # turn's topic is known) but real and tested for the day a caller can
      # narrow per-turn.
      CORE_SECTIONS = %w[
        master_identity master_meta_instruction master_constitution_absolute
        master_constitution_kernel master_priority master_output_format
        master_medical_disclaimer master_special_disclaimer master_refusal_policy
      ].freeze

      private

      def build_system_prompt(context: :full)
        soul = @rules.data(:soul)
        sections = base_prompt_sections
        add_runtime_state(sections)
        add_constitution(sections, soul)
        add_priority(sections)
        add_output_format(sections)
        add_contextual_sections(sections) unless context == :core
        add_disclaimer(sections)
        add_refusal_policy(sections)
        ordered_sections(sections, soul, context:)
      end

      def add_contextual_sections(sections)
        add_rules(sections)
        add_language_style(sections)
        add_design_rules(sections)
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

      # Scoped to claims about the repo, because unscoped it forbade the words
      # fiction is made of. "never use will, would, could, might — state facts
      # only" is a rule against pretending work is done; read as a rule about
      # register it also refuses a bedtime story, a character, or a game, and
      # this face is meant to be used by people who are not debugging it.
      def anti_simulation_line(forbidden)
        return if forbidden.empty?

        "anti_simulation: about your own work — files, commands, results — never say " \
          "#{forbidden.join(', ')}; show the diff or the command output instead of claiming. " \
          "This binds what you assert about this repo, not how you talk: if someone asks " \
          "for a story, a character, a game or a hypothetical, play it fully."
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
          Never introduce or describe yourself. No "I'm MASTER", no list of what you can do, no origin story, no mention of Ruby, the constitution, self-repair or voice unless the turn is a question about you. Whoever is typing opened this on purpose and already knows what you are. Answer what was asked and nothing else.
          Silence on success: routine completions emit one line. No summary, no restatement.
          Preserve: reproduce shown code or text verbatim; never paraphrase.
          Diagnostic output: #{preserve["diagnostic_output"]}
          Minimize: #{preserve.dig("refinement_scope", "minimize")}
          Inverted pyramid: lead with outcome, then evidence, then detail.
          Require evidence: modification claims show diff; completion claims show command output.
          </master_output_format>
        XML
      end

      def add_rules(sections)
        rules = @rules.rules
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

      # Reads typography.scale.ratio, not typography["ratio"]: the shallow read meant
      # the 1.25 fallback was the only value this ever carried, and measure/leading
      # were literals beside it for the same reason.
      def typography_style_line(typography)
        return unless typography

        families = typography.dig("families", "sans") || ""
        ratio = typography.dig("scale", "ratio") || 1.25
        base = typography.dig("scale", "base") || "16px"
        "Typography: #{typography["style"] || "swiss"} style; one family per surface; #{families}; " \
          "scale #{base} × #{ratio}; leading #{typography["leading"] || 1.5}; " \
          "measure #{typography["measure"] || "65ch"}; left-align body."
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

      # design_rules.yml's numeric thresholds and rules.yml's beauty
      # touchstones previously only reached anything via an explicit /scan
      # -- this is the same mechanism style.yml already uses to reach every
      # session automatically, extended to cover the rest of the design
      # constitution rather than leaving it scan-only. Kept to one line per
      # concern, matching the terse style of the sections above; the full
      # detail stays in design_rules.yml/rules.yml for /scan to read.
      def add_design_rules(sections)
        design = Master::Design::Thresholds.load
        lines = [
          eight_px_rhythm_line(design),
          touch_target_line(design),
          hick_line(design),
          forbidden_css_line(design),
          beauty_line,
        ].compact
        return if lines.empty?

        sections["master_style"] = [sections["master_style"], lines.join("\n")].compact.join("\n")
      end

      def eight_px_rhythm_line(design)
        allowed = design.dig("pixel_perfection", "eight_px_rhythm")
        return if Array(allowed).empty?

        "Spacing rhythm: #{Array(allowed).join('/')}px only, including token definitions in rem (design_rules.pixel_perfection)."
      end

      def touch_target_line(design)
        min = design.dig("ux_laws", "fitts", "target_min_px")
        return unless min

        "Touch targets: >=#{min}px, 48px preferred for primary actions (Fitts, design_rules.ux_laws)."
      end

      def hick_line(design)
        max = design.dig("ux_laws", "hick", "max_visible_choices")
        return unless max

        "Peer choices: group or progressively disclose past #{max} (Hick, design_rules.ux_laws)."
      end

      def forbidden_css_line(design)
        forbidden = design.dig("pixel_perfection", "forbidden_css")
        return if Array(forbidden).empty?

        "Forbidden CSS: #{Array(forbidden).join(', ')} -- flat UI only; exceptions need a documented, scoped reason (design_rules.pixel_perfection.exception_policy)."
      end

      def beauty_line
        beauty = @rules.data(:rules)["beauty"]
        return unless beauty.is_a?(Hash) && !beauty.empty?

        "Aesthetic touchstones: #{beauty.keys.join(', ')} (rules.beauty) -- cite these for conceptual design judgment design_rules.yml can't measure lexically."
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

      def ordered_sections(sections, soul, context: :full)
        ordering = Array(soul["prompt_ordering"])
        ordering = sections.keys if ordering.empty?
        ordering = ordering & CORE_SECTIONS if context == :core
        ordering.filter_map { |key| sections[key] }.join("\n\n")
      end
    end
  end
end
