# frozen_string_literal: true

module Master
  module Voice
    # The code and design style sections of Personality's system prompt: zsh,
    # Ruby, web, typography, heuristics, accessibility and the design rules, each
    # read from rules.yml sections through @rules. PersonalityPromptBuilder
    # includes this and decides which sections a prompt carries.
    module PersonalityStyleSections
      private

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
        zsh = @rules.data(:zsh) || @rules.data(:zsh_patterns)
        return [] unless zsh.is_a?(Hash) && !zsh.empty?

        [zsh_banned_line(zsh), zsh_replacement_line(zsh), zsh_pattern_line(zsh),
         zsh_ssh_line(zsh), zsh_economics_line(zsh)].compact
      end

      def zsh_banned_line(zsh)
        banned = Array(zsh["banned_commands"]).join(", ")
        "Zsh scripts: never use #{banned}. Use pure zsh parameter expansion and builtins instead." unless banned.empty?
      end

      def zsh_replacement_line(zsh)
        replacements = Array(zsh["forbidden_commands"]).first(8).filter_map do |row|
          "#{row["command"]} → #{row["replacement"]}" if row.is_a?(Hash)
        end
        "Zsh replacements: #{replacements.join("; ")}." unless replacements.empty?
      end

      def zsh_pattern_line(zsh)
        patterns = zsh["native_patterns"]
        return unless patterns.is_a?(Hash) && !patterns.empty?

        samples = patterns.first(6).map { |name, expr| "#{name}=#{expr}" }.join(", ")
        "Zsh native patterns: #{samples}."
      end

      def zsh_ssh_line(zsh)
        ssh = zsh["ssh_reading"]
        "SSH reading: #{ssh["rule"]}." if ssh.is_a?(Hash) && ssh["rule"]
      end

      def zsh_economics_line(zsh)
        economics = zsh.dig("token_economics", "philosophy").to_s.strip
        "Zsh token economics: #{economics.split(/\s+/).first(24).join(" ")}." unless economics.empty?
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
        by_number = Array(@rules.data(:rules)&.dig("rules"))
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
          markdown_style_line,
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

      # rules.yml markdown_style was codified for MASTER and the three coding
      # agents it names, and then read by nothing — data_reach counted it as one
      # of the two unnamed keys that put that census over its ceiling. Every
      # session writes markdown; the aesthetic that governs it belongs in the
      # same prompt as the design thresholds, not only in a file a scan reads.
      def markdown_style_line
        md = @rules.data(:rules)["markdown_style"]
        return unless md.is_a?(Hash)

        rules = Array(md["rules"])
        return if rules.empty?

        "Markdown: #{rules.join('; ')} (rules.markdown_style, aesthetic #{md['aesthetic']})."
      end

      def beauty_line
        beauty = @rules.data(:rules)["beauty"]
        return unless beauty.is_a?(Hash) && !beauty.empty?

        "Aesthetic touchstones: #{beauty.keys.join(', ')} (rules.beauty) -- cite these for conceptual design judgment design_rules.yml can't measure lexically."
      end
    end
  end
end
