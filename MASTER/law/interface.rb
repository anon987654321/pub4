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
  ask "Does this prompt renderer keep one compact, single-line grammar of location, repository state, meaningful transient phase/error state, and the shell prompt token? Look for decorative chrome, embedded newlines, duplicated state, expensive work on every redraw, or information that belongs behind /status, /doctor or /help. Return CLEAN when the prompt is already compact, single-line and bounded."
  fix "Keep one physical interactive line: location + repository state + meaningful transient phase/error + prompt token; cache or bound external probes; move detail to explicit status/help surfaces."
  # Quoted heredocs: the examples quote instance and local variables, and an
  # interpolating heredoc evaluates them against the Builder at load time —
  # one #{e.class} here once made every law definition crash the registry.
  bad <<~'X'
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
  bad <<~'X'
    rescue StandardError
      warn e
      nil
    end
  X
  good <<~'X'
    rescue StandardError => e
      @last_error = "#{e.class}: #{e.message}"
      warn_once("voice0: unavailable — #{@last_error}")
      fallback_or_false
    end
  X
end


Law.define(:CLI_ANALYZE_TARGET_ROUTING) do
  source "MASTER CLI — deterministic repository analysis targets"
  severity :error
  languages %i[yaml]
  path "MASTER/data/patterns.yml"
  scope :file
  ask "Does natural-language analysis of an explicit repository path enter the deterministic operator route instead of falling through to the model and guessing about file existence?"
  fix "Register analyze/analyse/inspect with a path capture and map it to the canonical review route."
  bad <<~'X'
    commands:
      review:
        patterns:
        - "\\b(?:review)\\s+(.+)"
  X
  good <<~'X'
    infer:
      commands:
        analyze:
          patterns:
          - "\\b(?:analyze|analyse|inspect)\\s+([\\w./-]+)"
          capture: path
  X
  detect do |text|
    section = text[/^    analyze:\s*\n(.*?)(?=^    [a-z][a-z0-9_-]*:\s*$|\z)/m, 1].to_s
    section.empty? || !section.match?(/analyze|analyse|inspect/) || !section.match?(/capture:\s*path/)
  end
end


Law.define(:CLI_FACE_DEDICATED_TTY) do
  source "Terminal discipline — full-screen face must not share line-editor input"
  severity :error
  languages %i[ruby]
  path "MASTER/lib/cli/command_registry.rb"
  scope :file
  ask "Does the /face command obtain an independent terminal stream instead of sharing Reline/session stdin with the full-screen face?"
  fix "Open /dev/tty and pass that handle as both the face input and output; close it after the face exits."
  bad <<~'X'
    Face::Window.new(turn:, event_bus: container[:bus]).run
  X
  good <<~'X'
    terminal = File.open("/dev/tty", "r+")
    Face::Window.new(turn:, event_bus: container[:bus], input: terminal, output: terminal).run
  X
  detect do |text|
    text.include?("Face::Window.new") &&
      !text.match?(/File\.open\(["']\/dev\/tty["'],\s*["']r\+["']\)/)
  end
end


Law.define(:CAPABILITY_STATUS_MUST_BE_TRUTHFUL) do
  source "OpenBSD-style status reporting — unavailable capabilities are not ready"
  severity :error
  languages %i[ruby]
  path "MASTER/lib/operator/services.rb"
  ask "Does a service status report readiness solely from a flag or optimistic default while the underlying capability may have failed? Status must derive from current observable capability state and preserve the failure reason."
  fix "Derive service state from the capability's actual health or retained error; report degraded or unavailable with the reason instead of ready."
  bad <<~'X'
    when "voice" then ENV["MASTER_TTS_DEGRADED"] == "1" ? "degraded" : "ready"
  X
  good <<~'X'
    when "voice"
      reason = Voice::Speech.last_error || Voice::Playback.last_error
      reason ? "degraded: #{reason}" : "ready"
  X
  detect do |text|
    text.match?(/when\s+["']voice["'][^\n]*ENV\[/) &&
      text.match?(/["']ready["']/)
  end
end
