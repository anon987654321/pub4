# frozen_string_literal: true

require_relative "personality_style_sections"

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
      # refusal policy); the code and design style sections, built in
      # PersonalityStyleSections, are only load-bearing when the turn is about code. Default
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

      include PersonalityStyleSections

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
        add_markdown_style(sections)
        add_design_rules(sections)
      end

      # The markdown_style section of data/rules.yml, which had no reader.
      #
      # Same shape as add_attention above: a section that names its own audience
      # and was never consulted. Its applies_to lists MASTER, claude, grok and
      # codex — every agent that writes markdown in this repo — and nothing in
      # the tree named the key, so the aesthetic it declares reached no prompt
      # and each agent invented its own house style. data_reach has counted it
      # as unread since it was restored after the 2026-08 read-modify-write that
      # reverted it.
      #
      # Read from the section rather than restated here, so adding a rule to the
      # yaml changes what the model is told. That is the whole reason the
      # section exists rather than a paragraph in a prompt.
      def add_markdown_style(sections)
        style = @rules.data(:markdown_style)
        return unless style.is_a?(Hash)

        rules = Array(style["rules"]).map(&:to_s).reject(&:empty?)
        return if rules.empty?

        aesthetic = style["aesthetic"].to_s.tr("_", " ").strip
        heading = aesthetic.empty? ? "Markdown you write:" : "Markdown you write follows the #{aesthetic} aesthetic:"
        lines = [heading, *rules.map { |rule| "- #{rule}" }]
        sections["master_style"] = [sections["master_style"], lines.join("\n")].compact.join("\n")
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
        protocol = Master::CLI::AttentionContext
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
          # code_preambles sat beside preambles and endings and reached no
          # prompt, so the two the model was told to avoid were enforced and
          # the filler comments were not -- which is the noise that actually
          # arrives in generated code.
          "comment_never: #{Array(strunk["code_preambles"]).first(4).join(' / ')}",
          strunk_scope_line(strunk),
          "evidence_only: show diff or file content; never assert; active voice",
          anti_simulation_line(anti_simulation),
          "</master_constitution>",
        ].compact.join("\n")
      end

      # The three lines above say what never to write and never said where, and
      # voice.yml has carried the answer with no reader: apply_to, never_apply_to
      # and safeguards. Unscoped, a ban on hedges and preambles reads as a ban on
      # the words an algorithm's own comment needs, which is the mistake
      # anti_simulation_line below had to be narrowed for in its own turn.
      def strunk_scope_line(strunk)
        applies = Array(strunk["apply_to"])
        never = Array(strunk["never_apply_to"])
        safeguards = Array(strunk["safeguards"])
        return if applies.empty? && never.empty? && safeguards.empty?

        [
          ("style_applies_to: #{applies.join(', ')}" unless applies.empty?),
          ("style_never_touches: #{never.join(', ')}" unless never.empty?),
          ("style_safeguards: #{safeguards.join(', ')}" unless safeguards.empty?),
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
        rules = all_rules
        return if rules.empty?

        sections["master_style"] = "<master_style>\nRules:\n#{rules.join("\n")}\n</master_style>"
      end

      # Every rule, from the one place that holds them.
      #
      # This used to concatenate soul's absolute.rules with law/'s, because a
      # rule about conduct could not be a Law — Builder demanded a detector and
      # none exists for "one SSH session". `conduct` removed that requirement and
      # the 47 moved, so there is no second list to merge and no question about
      # which file governs.
      #
      # A conduct rule states itself; a detector rule states its fix, which is
      # the imperative form of the same thing.
      #
      # Loaded lazily, and a failure is cosmetic: a prompt missing part of the
      # list is worse than one built without it, and neither should fail a turn.
      def all_rules
        require File.join(Master::ROOT, "law", "law") unless defined?(::Law)
        ::Law.load_all(File.join(Master::ROOT, "law")) if ::Law.rules.empty?
        ::Law.rules.values.map do |rule|
          "#{rule.id}: #{(rule.practice || rule.fix).to_s.gsub(/\s+/, ' ').strip}"
        end
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "PromptBuilder.all_rules", severity: :cosmetic)
        []
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
        refusal = @rules.data(:refusal_templates)
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
            context: "PromptBuilder.ordered_sections", severity: :load_bearing,
          )
        end
        ordering = ordering & CORE_SECTIONS if context == :core
        ordering.filter_map { |key| sections[key] }.join("\n\n")
      end
    end
  end
end
