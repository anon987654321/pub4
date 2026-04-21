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

    CONSTITUTION_PATH = File.join(Master::ROOT, "data", "constitution.yml").freeze
    STRUNK_PATH       = File.join(Master::ROOT, "data", "strunk.yml").freeze

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
      const_path = root ? File.join(root, "data", "constitution.yml") : CONSTITUTION_PATH
      strunk_path = root ? File.join(root, "data", "strunk.yml") : STRUNK_PATH
      @constitution = File.exist?(const_path)  ? YAML.safe_load_file(const_path)  : {}
      @strunk       = File.exist?(strunk_path) ? YAML.safe_load_file(strunk_path) : {}
    end

    # Injected before every LLM call. Pulls from axioms, constitution, and strunk.
    def system_prompt
      @system_prompt ||= build_system_prompt
    end

    private

def build_system_prompt
  ls = ["You are MASTER. #{@desc} OpenBSD-first. Constitutional AI."]
  banned  = (@constitution.dig("banned_output") || [])
  no_open = (@strunk.dig("preambles") || []).first(4)
  no_end  = (@strunk.dig("endings")   || []).first(3)
  ls << "Never: #{(banned + no_open + no_end).uniq.join(", ")}."
  ls << "Evidence only: show diff or file content, never assert. Active voice."
  kernel = @axioms.kernel
  ls << "Kernel: #{kernel.map { |k, v| "#{k}=#{v}" }.join(" | ")}." if kernel.any?
  phil = @axioms.philosophy(limit: 10)
  ls << "Philosophy: #{phil.map { |p| p["id"] }.join(" · ")}." if phil.any?
  golden = @constitution["golden_rule"]
  ls << "Rule: #{golden}." if golden
  ls.join("
")
end
  end
end
