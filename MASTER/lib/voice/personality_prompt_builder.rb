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
        add_attention(sections)
        add_language_style(sections)
        add_design_rules(sections)
      end

      # The breadcrumb protocol, from the file that defines it.
      #
      # data/attention_context.yml has specified map/zoom/act/target/parent since
      # it was written, along with when to emit one and when silence is better.
      # Its own runtime_uses says "include in prompt-builder metadata for long
      # agentic tasks". Nothing did: the only reference to AttentionContext in
      # the tree was a /help listing naming the file, and the word breadcrumb
      # appeared nowhere in a built prompt.
      #
      # Read from the protocol rather than restated here, so the vocabulary has
      # one source and adding a zoom or an act to the yaml changes the prompt.
      def add_attention(sections)
        protocol = Master::Ground::AttentionContext
        philosophy = protocol.protocol.dig("protocol", "philosophy").to_s.strip
        return if philosophy.empty?

        sections["master_attention"] = <<~XML.strip
          <master_attention>
          #{philosophy}
          Format: #{protocol.template(:compact_text)}
          zoom: #{protocol.valid_zooms.join(' / ')}
          act: #{protocol.valid_acts.join(' / ')}
          Three moves, and naming one is the point of the breadcrumb: stay on the current map,
          `deep` to push a child onto it, `out` to pop back to a parent. On `out`, the work under
          the popped node is finished with — summarise it in one line and stop carrying its detail.
          Emit when: #{Array(protocol.protocol["when_to_emit"]).join(', ')}
          Stay silent when: #{Array(protocol.protocol["when_not_to_emit"]).join(', ')}
          </master_attention>
        XML
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "PromptBuilder.add_attention", severity: :cosmetic)
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
          1) Constitutional rules and anti-simulation
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

      # One list called Rules, from both places that hold one.
      #
      # soul holds the rules no detector can check — read before write, surface
      # errors first, verify the instrument. law/ holds the rules a detector does
      # check, and its `fix` line is that rule's one wording. Emitting law/ here
      # is what lets soul stop restating it: FAIL_VISIBLY was written out in
      # soul, in law/ and in rules.yml, three files and three wordings for one
      # rule, with no way for a reader to tell which governed.
      #
      # Not two labelled blocks. Whether a detector happens to exist is a fact
      # about the tooling, not a different kind of rule, and splitting the list
      # on it is the same mistake as the aesthetic_rules section that had to be
      # collapsed for the same reason.
      def add_rules(sections)
        rules = @rules.rules
        detected = detected_rules
        return if rules.empty? && detected.empty?

        thresholds = @rules.thresholds
        substitutions = {
          max_lines: thresholds.dig("class", "max_lines") || 200,
          max_methods: thresholds.dig("class", "max_methods") || 6,
        }
        held = rules.map { |id, statement| "#{id}: #{statement % substitutions}" }
        sections["master_style"] = "<master_style>\nRules:\n#{(held + detected).join("\n")}\n</master_style>"
      end

      # Loaded lazily, and a failure here is cosmetic: a prompt missing part of
      # the list is worse than one built without it, and neither is a reason to
      # fail the turn.
      def detected_rules
        require File.join(Master::ROOT, "law", "law") unless defined?(::Law)
        ::Law.load_all(File.join(Master::ROOT, "law")) if ::Law.rules.empty?
        ::Law.rules.values.map { |rule| "#{rule.id}: #{rule.fix}" }
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "PromptBuilder.detected_rules", severity: :cosmetic)
        []
      end

      def add_language_style(sections)
        lines = zsh_style_lines
        lines << stack_line if stack_line
        style = @rules.data(:ruby_style)
        if style.is_a?(Hash) && !style.empty?
          lines.concat(ruby_style_lines(style))
          lines.concat(web_style_lines(style))
          append_directives(sections, style)
        end
        return if lines.empty?

        sections["master_style"] = [sections["master_style"], lines.join("\n")].compact.join("\n")
      end

      # The versions this fleet actually runs, so advice lands on them rather
      # than whatever the model saw last. These 58 leaf values sat under
      # style.ruby.rails_stack and nothing had ever read one of them.
      def stack_line
        s = @rules.data(:rails_stack)
        return unless s.is_a?(Hash) && s["rails"]

        "Stack: Rails #{s['rails']}, Turbo #{s['turbo_rails']}, Stimulus #{s['stimulus']}, " \
          "#{s['asset_pipeline']} + #{s['javascript']}, #{s['queue']}/#{s['cache']}/#{s['cable']}, #{s['database']}."
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
          optional_rule("Naming", style.dig("universal", "naming_rule")),
          optional_rule("String methods", style.dig("ruby", "prefer_string_methods_rule")),
          optional_rule("Gems", style.dig("ruby", "outsource_to_gems_rule")),
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
          heuristics_style_line,
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

      # Derived from the hash, not restating it. This returned a fixed sentence
      # for as long as it existed, so style.css.layer_order, .units_* and
      # .forbidden described a line nothing read them for — editing any of them
      # changed nothing anywhere, which is the whole inert-config defect in one
      # method.
      def css_style_line(css)
        return unless css

        parts = ["CSS: #{css['targeting'] == 'bare_tag_first' ? 'tag selectors first, classes last' : css['targeting']}"]
        parts << "@layer #{Array(css['layer_order']).join('/')}" if css["layer_order"]
        parts << "#{css['units_length']} units" if css["units_length"]
        parts << "avoid: #{Array(css['forbidden']).first(3).join('; ')}" if css["forbidden"]
        parts.join("; ")
      end

      # Reads typography.scale.ratio, not typography["ratio"]: the shallow read meant
      # the 1.25 fallback was the only value this ever carried, and measure/leading
      # were literals beside it for the same reason.
      def typography_style_line(typography)
        return unless typography

        families = typography["families_sans"] || ""
        ratio = typography["scale_ratio"] || 1.25
        base = typography["scale_base"] || "16px"
        "Typography: #{typography["style"] || "swiss"} style; one family per surface; #{families}; " \
          "scale #{base} × #{ratio}; leading #{typography["leading"] || 1.5}; " \
          "measure #{typography["measure"] || "65ch"}; left-align body."
      end

      # Read from the rules that enforce them, not from a second list beside
      # them. style.nielsen_heuristics restated NN/g's ten as {id, name, rule}
      # while the registry already carried nine as scored entries whose `source`
      # names the heuristic and whose `name` is the requirement — and the prompt
      # only ever emitted the labels, so the restated `rule:` text reached
      # nothing. The tenth, error prevention, is GUARD_EXPENSIVE_OPS.
      # Two spellings appear in the sources ("Heuristic #5" and "heuristic 5"),
      # and PROGRESSIVE_DISCLOSURE cites NN/g with no number, so it is grouped
      # out. Grouping also keeps the list at ten rather than twelve: #1 is
      # claimed by both SYSTEM_STATUS and FEEDBACK_LOOPS.
      def heuristics_style_line
        by_number = Array(@rules.data(:rules)&.dig("rules", "unit"))
                    .select { |r| r["source"].to_s.include?("Nielsen") }
                    .group_by { |r| r["source"][/[Hh]euristic #?(\d+)/, 1] }
                    .reject { |number, _| number.nil? }
        return if by_number.empty?

        listed = by_number.sort_by { |number, _| number.to_i }
                          .map { |number, rs| "#{number}. #{rs.map { |r| r['name'] }.join(' / ')}" }
        "Nielsen heuristics enforced: #{listed.join('; ')}."
      end

      def accessibility_style_line(accessibility)
        return unless accessibility

        target = accessibility["target"] || "wcag_2_2_aaa"
        "Accessibility target: #{target}; keyboard-complete; focus-visible; " \
          "respect prefers-reduced-motion + color-scheme; never tabindex>0; never autoplay sound."
      end

      def append_directives(sections, style)
        # style.operator_directives has never existed — the operator's standing
        # rules are `operator_principles` at the root, already read by
        # Ground::Constitution. This read was always nil.
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

      # A section built and left out of prompt_ordering is dropped without a
      # word, which is how a whole block can be written, tested by hand, and
      # never reach a model. Logged rather than raised: a missing section is a
      # worse prompt, not a broken turn.
      def ordered_sections(sections, soul, context: :full)
        ordering = Array(soul["prompt_ordering"])
        ordering = sections.keys if ordering.empty?
        unordered = sections.keys - ordering - (context == :core ? [] : [])
        unless unordered.empty?
          Master::Ground::Swallow.log(
            RuntimeError.new("prompt sections built but absent from soul prompt_ordering: #{unordered.join(', ')}"),
            context: "PromptBuilder.ordered_sections", severity: :load_bearing
          )
        end
        ordering = ordering & CORE_SECTIONS if context == :core
        ordering.filter_map { |key| sections[key] }.join("\n\n")
      end
    end
  end
end
