# frozen_string_literal: true

# MASTER interface laws: terminal, transport and capability-facing presentation.
# Keep these together so interface defects become executable law without growing
# universal.rb into another monolith.

Law.define(:NO_TRANSPORT_WRAPPER_IN_SOURCE) do
  source "MASTER source integrity — presentation wrappers do not belong in source files"
  severity :error
  languages %i[ruby]
  scope :file
  path_exclude %r{/law/}
  detect do |text|
    text.match?(/\A\s*<(?:sub|sup|pre|code)>/i) ||
      text.match?(/\n\s*<\/(?:sub|sup|pre|code)>\s*\z/i)
  end
  fix "Remove presentation/transport wrapper markup from the source file and preserve its Ruby contents verbatim."
  bad <<~'X'
    <sub>
    # frozen_string_literal: true
    require "fileutils"
    end
    </sub>
  X
  good <<~'X'
    # frozen_string_literal: true

    require "fileutils"

    def run = true
  X
end

Law.define(:CLI_TREE_TARGET_RESOLUTION) do
  source "MASTER CLI — four-tree target addressing"
  severity :error
  languages %i[ruby]
  path "MASTER/lib/cli/"
  ask "When an operator explicitly names MASTER, RAILS, OPENBSD or STUDIO, does the command resolve that target from the repository root through the canonical target resolver rather than assuming the current working directory is MASTER? Return CLEAN when every explicit sibling-tree target follows the shared resolver contract."
  fix "Resolve explicit four-tree targets from Master::REPO_ROOT through TargetResolver; never reinterpret a sibling tree relative to MASTER/lib or the current process directory."
  bad <<~X
    target = File.expand_path("STUDIO/lora", Dir.pwd)
  X
  good <<~X
    target = resolve_target("STUDIO/lora")
  X
end

Law.define(:CLI_PROMPT_COMPOSITION) do
  source "OpenBSD ksh/ash restraint; fish/zsh line editing; Starship bounded prompt composition"
  severity :info
  mode :opportunity
  languages %i[ruby]
  path "MASTER/lib/voice/renderer/"
  ask "Does this prompt renderer keep one compact grammar of location, repository state, meaningful transient phase/error state, and the shell prompt token? Look for decorative chrome, duplicated state, expensive work on every redraw, or information that belongs behind /status, /doctor or /help. Return CLEAN when the prompt is already compact and bounded."
  fix "Keep the prompt to location + repository state + meaningful transient phase/error + prompt token; cache or bound external probes; move detail to explicit status/help surfaces."
  bad <<~X
    def prompt
      system("git status")
      "◉ #{@path} [model=#{@model} tokens=#{@tokens} memory=#{@memory}]"
    end
  X
  good <<~X
    def prompt
      [path, branch, phase, token].compact.join(" ") + " "
    end
  X
end

Law.define(:VOICE_FAILURES_ARE_ACTIONABLE) do
  source "OpenBSD-style explicit failure reporting — degraded capability is state, not noise"
  severity :info
  mode :opportunity
  languages %i[ruby]
  path "MASTER/lib/voice/"
  ask "When synthesis, transport, or playback fails, does the runtime produce one bounded actionable state, preserve a useful last_error, and use the declared fallback chain without replaying or spawning uncontrolled work? Return CLEAN when the failure path is already explicit and bounded."
  fix "Return an explicit failure/result, retain the reason for /status or /doctor, rate-limit repeated diagnostics, and fall through only to declared voice/audio fallbacks."
  bad <<~X
    rescue StandardError
      warn e
      nil
    end
  X
  good <<~X
    rescue StandardError => e
      @last_error = "#{e.class}: #{e.message}"
      warn_once("voice0: unavailable — #{@last_error}")
      fallback_or_false
    end
  X
end
