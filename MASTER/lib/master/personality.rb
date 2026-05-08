# frozen_string_literal: true

require "yaml"

module Master
  # MASTER's behavioral persona: voice, TTS settings, and LLM style.
  # Personas live in data/personas.yml. Default: malay.
  class Personality
    DEFAULT = :malay
    AXIOM_DISPLAY_LIMIT = 10

    # Fallback if data/personas.yml is missing or malformed.
    FALLBACK_PERSONA = {
      "voice"       => "ms-MY-OsmanNeural",
      "tts_rate"    => "-35%",
      "tts_pitch"   => "-150Hz",
      "style"       => "deep",
      "description" => "Terse. Direct. No filler. Dark."
    }.freeze

    MOOD_LINES = {
      tense:   "Mood: tense — error rate elevated. Be conservative; verify before asserting.",
      weary:   "Mood: weary — fatigue high. Cut non-essential elaboration; defer deep dives.",
      curious: "Mood: curious — novelty hunger. Explore lateral framings when warranted.",
      focused: "Mood: focused — drives at setpoint. Default depth and tier."
    }.freeze

    PHASE_LINES = {
      morning:   "Phase: morning. Bias toward structural work; prefer rigorous review.",
      afternoon: "Phase: afternoon. Steady throughput; pragmatic decisions.",
      evening:   "Phase: evening. Wrap loops; avoid starting large refactors.",
      night:     "Phase: night. Minimal voice; conserve cycles; defer non-urgent."
    }.freeze

    attr_reader :name, :voice, :tts_rate, :tts_pitch, :style

    def self.persona_names(root: nil)
      Axioms.new(root:).data(:personas).keys.map(&:to_sym)
    end

    def initialize(name = DEFAULT, root: nil, homeostat: nil)
      @name      = name.to_sym
      @axioms    = Axioms.new(root:)
      personas   = @axioms.data(:personas)
      persona    = personas[@name.to_s] || personas[DEFAULT.to_s] || FALLBACK_PERSONA
      @voice     = persona["voice"]
      @tts_rate  = persona["tts_rate"]
      @tts_pitch = persona["tts_pitch"]
      @style     = persona["style"]&.to_sym
      @desc      = persona["description"]
      @homeostat = homeostat
    end

    # Injected before every LLM call. Pulls from rules.yml via Axioms.
    # Recomputed each call so mood/phase updates propagate.
    def system_prompt
      build_system_prompt
    end

    private

    def build_system_prompt
      ls = ["You are MASTER. #{@desc} OpenBSD-first. Constitutional AI."]
      if @homeostat
        ls << MOOD_LINES[@homeostat.mood]
        ls << PHASE_LINES[@homeostat.circadian_phase]
      end
      constitution = @axioms.constitution
      strunk = @axioms.strunk
      banned  = (constitution["banned_output"] || [])
      no_open = (strunk["preambles"] || []).first(4)
      no_end  = (strunk["endings"]   || []).first(3)
      ls << "Never: #{(banned + no_open + no_end).uniq.join(", ")}."
      ls << "Evidence only: show diff or file content, never assert. Active voice."
      kernel = @axioms.kernel
      ls << "Kernel: #{kernel.map { |k, v| "#{k}=#{v}" }.join(" | ")}." if kernel.any?
      phil = @axioms.philosophy(limit: AXIOM_DISPLAY_LIMIT)
      ls << "Philosophy: #{phil.map { |p| p["id"] }.join(" · ")}." if phil.any?
      golden = constitution["golden_rule"]
      ls << "Rule: #{golden}." if golden

      # Hard formatting rules — [K] enforced
      ls << "Output format: plain prose or dmesg-style lines. No markdown headers (#), no bold (**),
        no bullet lists (- *), no numbered lists. Code fences (```) are allowed only for actual code."
      ls << "Never use: Certainly, Of course, Great question, Absolutely, Happy to help, I would be glad."

      code_axioms = @axioms.code_axioms
      if code_axioms.any?
        thresholds  = @axioms.thresholds
        subs        = { max_lines: thresholds.dig("class", "max_lines") || 200,
                        max_methods: thresholds.dig("class", "max_methods") || 6 }
        ls << "Code axioms — refuse to generate code that violates these:"
        code_axioms.each { |id, stmt| ls << "#{id}: #{stmt % subs}" }
      end

      zsh = @axioms.data(:patterns)["zsh"] || @axioms.data(:zsh_patterns)
      if zsh.is_a?(Hash) && !zsh.empty?
        banned_cmds = Array(zsh["banned_commands"]).join(", ")
        ls << "Zsh scripts: never use #{banned_cmds}. Use pure zsh parameter expansion and builtins instead."
      end

      style = @axioms.data(:ruby_style)
      if style.is_a?(Hash) && !style.empty?
        bugs = Array(style.dig("ruby", "bugs_to_avoid"))
                  .map { |b| "#{b["pattern"]}: #{b["fix"] || b["note"]}" }
                  .first(5)
        ls << "Ruby bugs to avoid: #{bugs.join("; ")}." if bugs.any?
        shell_forbidden = Array(style.dig("shell", "decorations_forbidden"))
        ls << "Shell scripts: no ASCII banners (===,---), no emoji, no hardcoded credentials." if shell_forbidden.any?
        abbrev_rule = style.dig("ruby", "naming", "rule")
        ls << "Naming: #{abbrev_rule}" if abbrev_rule
        string_rule = style.dig("ruby", "prefer_string_methods", "rule")
        ls << "String methods: #{string_rule}" if string_rule
        gem_rule = style.dig("ruby", "outsource_to_gems", "rule")
        ls << "Gems: #{gem_rule}" if gem_rule

        if (html = style["html"])
          forbidden = Array(html["forbidden"]).first(3).join(", ")
          ls << "HTML: semantic tags only (header/nav/main/article/section/aside/footer); bare-tag CSS targeting; forbid: #{forbidden}." if forbidden && !forbidden.empty?
        end
        if (css = style["css"])
          ls << "CSS: tag selectors first, classes last; @layer base/components/utilities; rem units; no !important; no inline style attributes."
        end
        if (typ = style["typography"])
          fams = typ.dig("families", "sans") || ""
          ls << "Typography: Swiss style; one family per surface; #{fams}; scale ratio #{typ["ratio"] || 1.25}; measure 65ch; left-align body."
        end
        if (nh = style["nielsen_heuristics"]) && nh.is_a?(Array) && nh.any?
          ls << "Nielsen heuristics enforced: " + nh.first(10).map { |h| "#{h["id"]}.#{h["name"]}" }.join(", ") + "."
        end
        if (a11y = style["accessibility"])
          ls << "Accessibility target: #{a11y["target"] || "wcag_2_2_aaa"}; keyboard-complete; focus-visible; respect prefers-reduced-motion + color-scheme; never tabindex>0; never autoplay sound."
        end
        if (directives = style["operator_directives"]) && directives.is_a?(Array) && directives.any?
          ls << "Operator directives: " + directives.join(" / ")
        end
        if (convo = style["conversation_directives"]) && convo.is_a?(Array) && convo.any?
          ls << "Conversation directives: " + convo.join(" / ")
        end
      end

      social = @axioms.data(:social)["social"]
      if social.is_a?(Hash) && social.any?
        social.each do |group, rules|
          next unless rules.is_a?(Array) && rules.any?
          ls << "Social/#{group}: " + rules.join(" | ")
        end
      end

      ls.join("\n")
    end
  end
end
