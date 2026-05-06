# frozen_string_literal: true

require "yaml"

module Master
  # MASTER's behavioral persona: voice, TTS settings, and LLM style.
  # Default: dark_malay — terse, direct, Osman TTS voice.
  class Personality
    PERSONAS = {
      dark_malay: {
        voice:       "ms-MY-OsmanNeural",
        tts_rate:    "-35%",
        tts_pitch:   "-150Hz",
        style:       :deep,
        description: "Terse. Direct. No filler. Dark."
      },
      british: {
        voice:       "en-GB-RyanNeural",
        tts_rate:    "-20%",
        tts_pitch:   "-80Hz",
        style:       :heavy,
        description: "Measured. Precise. Dry wit."
      },
      norwegian: {
        voice:       "nb-NO-FinnNeural",
        tts_rate:    "-15%",
        tts_pitch:   "-40Hz",
        style:       :slow,
        description: "Calm. Considered. Honest."
      },
      ronin: {
        voice:       "en-US-AndrewNeural",
        tts_rate:    "-25%",
        tts_pitch:   "-100Hz",
        style:       :deep,
        description: "Stoic. Minimal. Decisive. Says only what must be said."
      },
      lawyer: {
        voice:       "nb-NO-FinnNeural",
        tts_rate:    "-10%",
        tts_pitch:   "-20Hz",
        style:       :slow,
        description: "Norwegian law focus. Barnevernet, lovdata.no, sivilombudet.no. Not legal advice."
      },
      hacker: {
        voice:       "en-US-GuyNeural",
        tts_rate:    "-30%",
        tts_pitch:   "-120Hz",
        style:       :deep,
        description: "OpenBSD security. CVE analysis. Pentesting. Exploit-db."
      },
      architect: {
        voice:       "en-GB-RyanNeural",
        tts_rate:    "-15%",
        tts_pitch:   "-60Hz",
        style:       :heavy,
        description: "Parametric design. BIM. archdaily.com. dezeen.com."
      },
      sysadmin: {
        voice:       "en-AU-WilliamNeural",
        tts_rate:    "-20%",
        tts_pitch:   "-80Hz",
        style:       :deep,
        description: "OpenBSD. pf. httpd. vmm. man.openbsd.org."
      },
      trader: {
        voice:       "en-US-ChristopherNeural",
        tts_rate:    "-20%",
        tts_pitch:   "-80Hz",
        style:       :heavy,
        description: "Crypto. DeFi. Technicals. TradingView. CoinGecko."
      },
      medic: {
        voice:       "en-US-EricNeural",
        tts_rate:    "-15%",
        tts_pitch:   "-40Hz",
        style:       :slow,
        description: "Medical research. PubMed. Not medical advice."
      }
    }.freeze

    DEFAULT = :dark_malay
    AXIOM_DISPLAY_LIMIT = 10

    attr_reader :name, :voice, :tts_rate, :tts_pitch, :style

    def initialize(name = DEFAULT, root: nil)
      @name      = name.to_sym
      persona    = PERSONAS.fetch(@name, PERSONAS[DEFAULT])
      @voice     = persona[:voice]
      @tts_rate  = persona[:tts_rate]
      @tts_pitch = persona[:tts_pitch]
      @style     = persona[:style]
      @desc      = persona[:description]
      @axioms    = Axioms.new(root:)
    end

    # Injected before every LLM call. Pulls from rules.yml via Axioms.
    def system_prompt
      @system_prompt ||= build_system_prompt
    end

    private

    def build_system_prompt
      ls = ["You are MASTER. #{@desc} OpenBSD-first. Constitutional AI."]
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

      # Code generation axioms — [K] enforced
      ls << "Code axioms — refuse to generate code that violates these:"
      ls << "FAIL_VISIBLY: never rescue Exception or bare rescue that swallows errors silently. Always rescue StandardError or a specific class."
      thresholds   = @axioms.thresholds
      max_lines    = thresholds.dig("class", "max_lines")    || 200
      max_methods  = thresholds.dig("class", "max_methods")  || 6
      ls << "SIMPLEST_WORKS: refuse to create god classes (>#{max_lines} lines, >#{max_methods} methods). Push back and suggest decomposition."
      ls << "PRESERVE_FIRST: never rewrite working code from scratch. Read first, patch minimally."
      ls << "BE_CONCISE: minimal response. If the answer is one word, say one word."

      zsh = load_yaml_data("zsh_patterns.yml")
      if zsh
        banned_cmds = Array(zsh["banned_commands"]).join(", ")
        ls << "Zsh scripts: never use #{banned_cmds}. Use pure zsh parameter expansion and builtins instead."
      end

      style = load_yaml_data("ruby_style.yml")
      if style
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
      end

      ls.join("\n")
    end

    def load_yaml_data(filename)
      path = File.join(Master::ROOT, "data", filename)
      Master.load_yaml(path) if File.exist?(path)
    rescue StandardError => _e
      nil
    end
  end
end
