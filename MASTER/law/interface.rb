# frozen_string_literal: true

# MASTER interface laws: terminal, transport and capability-facing presentation.
# Keep these together so interface defects become executable law without growing
# universal.rb into another monolith.

Law.define(:NO_TRANSPORT_WRAPPER_IN_SOURCE) do
  source "MASTER source integrity — presentation wrappers do not belong in source files"
  scope :file
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
  ask "When an operator explicitly names MASTER, RAILS, OPENBSD or STUDIO, does the command resolve that target from the repository root through the canonical target resolver rather than assuming the current working directory is MASTER? Return CLEAN when every explicit sibling-tree target follows the shared resolver contract."
  fix "Resolve explicit four-tree targets from Master::REPO_ROOT through TargetResolver; never reinterpret a sibling tree relative to MASTER/lib or the current process directory."
  bad <<~X
    target = File.expand_path("STUDIO/replicate/lora", Dir.pwd)
  X
  good <<~X
    target = resolve_target("STUDIO/replicate/lora")
  X
end

Law.define(:CLI_PROMPT_COMPOSITION) do
  source "OpenBSD dmesg console discipline; shell line editing remains the input transport"
  ask "Does the interactive prompt remain a restrained OpenBSD-console line that shows the checkout/tree, current directory, active conversation destination, Git state, meaningful phase/error state and input token, with no Starship/powerline-style segments or decorative emphasis? Is it bounded, single-line, plain in scrollback and cheap to redraw? Return CLEAN when it follows the dmesg-first house style."
  fix "Keep one compact text line with checkout/tree-relative path, active destination, plain Git state, phase and shell token. Prefer ASCII and stable spacing; avoid badges, icon glyphs, color-coded segments, boxes and duplicated status. Cache or bound Git probes and move detail to /status, /doctor or /help."
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

Law.define(:OPENBSD_DMESG_CONSOLE_STYLE) do
  source "OpenBSD dmesg — xsa/openbsd-dmesgs and Master::Trace::Dmesg"
  ask "For startup, status, progress and operational events, does CLI output follow the native console idiom: append-only, one factual event per line, a stable subsystem0: or unit0 at parent: prefix, truthful status, and useful scrollback? Look for banners, decorative panels, ASCII art outside the face, badge-like status, repeated progress chatter, and information hidden behind color alone. Conversational replies may retain plain Markdown when structure serves the content. Return CLEAN when operational output remains clear in a pipe, serial terminal and saved transcript."
  fix "Use Master::Trace::Dmesg's existing unit0: grammar for operational events; emit one concise factual line per event, order events by occurrence, keep state and recovery explicit, and preserve plain-text meaning without relying on ANSI or animation. Conversational replies may use restrained, width-aware Markdown. Do not create a second event logging format."
  bad <<~'X'
    ╭─ MASTER ───────────────────────────╮
    │  ◉ ONLINE  MODEL: ready  TOKENS 5k │
    ╰───────────────────────────────────╯
  X
  good <<~'X'
    model0: ready
    context0: 5k/128k
    fix0 at scan0: 3 files changed
  X
end

Law.define(:VOICE_FAILURES_ARE_ACTIONABLE) do
  source "OpenBSD-style explicit failure reporting — degraded capability is state, not noise"
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
  ask "Does a status, progress, success, pending, sent or delivered label, or a service readiness report, " \
      "claim a state the system has not observed: from a flag, an optimistic default, or before the " \
      "server or capability answered? State must derive from observed outcome and keep the failure reason."
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

Law.define(:SIGNATURE_MOMENT) do
  source "Interaction design — distinctive, frequent, functional moments"
  ask "Does this product surface have one deliberately distinctive interaction that users encounter often, improves the task rather than merely decorating it, matches the product's character, and remains effortless and accessible? Return CLEAN when an existing interaction already serves this role."
  fix "Choose one existing high-frequency interaction and give it immediate, restrained, distinctive feedback. Do not invent a feature solely for delight, duplicate the pattern elsewhere, or make motion or haptics the only signal."
  bad "Add a decorative animation with no relationship to the user's action."
  good "Make one frequent action produce immediate visual state, optional tactile feedback, and a clear success or failure result."
end

Law.define(:DIRECT_MANIPULATION_FEEDBACK) do
  source "Direct manipulation — immediate perceptual feedback"
  ask "When a user directly presses, drags, swipes, or dismisses something, does the interface acknowledge that input immediately rather than waiting for a delayed release or network result? Check pointer, keyboard, touch, visual state, and failure recovery together."
  fix "Respond at input start with a small state change, keep the gesture tied to the pointer while it moves, and retain a non-motion keyboard equivalent. Do not make the early feedback imply success before the action is actually committed."
  bad "click -> request -> finally show any indication that the press happened"
  good "pointerdown/active -> immediate press state; commit -> explicit success or failure state"
end

Law.define(:WAITING_STATE_MEANING) do
  source "Interaction status — useful feedback during dead time"
  ask "When a user is waiting for a meaningful result, does the surface identify what is happening or what is being prepared, rather than exposing only a generic spinner or unexplained motion? Keep the message brief, truthful, localised, and independent of animation."
  fix "Expose a short status label alongside the existing progress or skeleton state. Keep it accurate and persistent long enough to orient the user; never invent progress or use animation as the only meaning."
  bad "<div class=\"spinner\" aria-label=\"Loading\"></div>"
  good "<div aria-busy=\"true\"><span>Loading results…</span><div class=\"skeleton\" aria-hidden=\"true\"></div></div>"
end

