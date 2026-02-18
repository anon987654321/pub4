# frozen_string_literal: true

module MASTER
  # CommandRegistry - single source of truth for command metadata.
  module CommandRegistry
    extend self

    COMMANDS = {
      ask: { desc: "Ask the LLM a question", usage: "ask <question>", group: :query, aliases: [] },
      refactor: { desc: "Refactor a file with 6-phase analysis", usage: "refactor <file>", group: :query, aliases: %w[autofix] },
      chamber: { desc: "Multi-model deliberation", usage: "chamber <file>", group: :query, aliases: [] },
      evolve: { desc: "Self-improvement cycle", usage: "evolve [path]", group: :query, aliases: [] },
      opportunities: { desc: "Find improvements", usage: "opportunities [path]", group: :query, aliases: %w[opps] },
      hunt: { desc: "8-phase bug analysis", usage: "hunt <file>", group: :analysis, aliases: [] },
      critique: { desc: "Constitutional validation", usage: "critique <file>", group: :analysis, aliases: [] },
      learn: { desc: "Show matching learned patterns", usage: "learn <file>", group: :analysis, aliases: [] },
      conflict: { desc: "Detect principle conflicts", usage: "conflict", group: :analysis, aliases: [] },
      scan: { desc: "Scan for code smells", usage: "scan [path]", group: :analysis, aliases: [] },
      session: { desc: "Session management", usage: "session [new|save|load]", group: :session, aliases: [] },
      sessions: { desc: "List saved sessions", usage: "sessions", group: :session, aliases: [] },
      forget: { desc: "Undo last exchange", usage: "forget", group: :session, aliases: %w[undo] },
      summary: { desc: "Conversation summary", usage: "summary", group: :session, aliases: [] },
      capture: { desc: "Capture session insights", usage: "capture", group: :session, aliases: %w[session-capture] },
      "review-captures": { desc: "Review captured insights", usage: "review-captures", group: :session, aliases: [] },
      status: { desc: "System status", usage: "status", group: :system, aliases: [] },
      budget: { desc: "Budget remaining", usage: "budget", group: :system, aliases: [] },
      context: { desc: "Context window usage", usage: "context", group: :system, aliases: [] },
      history: { desc: "Cost history", usage: "history", group: :system, aliases: [] },
      health: { desc: "Health check", usage: "health", group: :system, aliases: [] },
      doctor: { desc: "Deep diagnostics", usage: "doctor [--verbose]", group: :system, aliases: [] },
      bootstrap: { desc: "First-run setup", usage: "bootstrap", group: :system, aliases: [] },
      "history-dig": { desc: "Recover deleted historical file", usage: "history-dig [master.yml|master.json]", group: :system, aliases: [] },
      codify: { desc: "Show/export codified design rules", usage: "codify [export-json]", group: :system, aliases: [] },
      "style-guides": { desc: "List/sync style guides", usage: "style-guides [sync]", group: :system, aliases: %w[styleguides] },
      help: { desc: "Show this help", usage: "help [command]", group: :util, aliases: %w[?] },
      speak: { desc: "Text-to-speech", usage: "speak <text>", group: :util, aliases: %w[say] },
      shell: { desc: "Interactive shell", usage: "shell", group: :util, aliases: [] },
      clear: { desc: "Clear screen", usage: "clear", group: :util, aliases: [] },
      exit: { desc: "Exit MASTER", usage: "exit", group: :util, aliases: %w[quit] },
      model: { desc: "Select LLM model", usage: "model <name>", group: :system, aliases: %w[use] },
      models: { desc: "List models", usage: "models", group: :system, aliases: [] },
      pattern: { desc: "Select executor pattern", usage: "pattern <name>", group: :system, aliases: %w[mode] },
      patterns: { desc: "List executor patterns", usage: "patterns", group: :system, aliases: %w[modes] },
      persona: { desc: "Manage active persona", usage: "persona <name|off>", group: :system, aliases: [] },
      personas: { desc: "List personas", usage: "personas", group: :system, aliases: [] },
      workflow: { desc: "Workflow control", usage: "workflow <cmd>", group: :system, aliases: [] },
      queue: { desc: "Queue operations", usage: "queue <cmd>", group: :system, aliases: [] },
      harvest: { desc: "Data harvesting", usage: "harvest <target>", group: :system, aliases: [] },
      replicate: { desc: "Generate media via Replicate", usage: "replicate <prompt>", group: :util, aliases: %w[repligen generate-image generate-video] },
      postpro: { desc: "Post-processing operations", usage: "postpro <operation> <path|url>", group: :util, aliases: %w[enhance upscale] },
    }.freeze

    def help_commands
      COMMANDS.transform_values { |v| { desc: v[:desc], usage: v[:usage], group: v[:group] } }
    end

    def primary_commands
      COMMANDS.keys.map(&:to_s)
    end

    def autocomplete_commands
      (primary_commands + COMMANDS.values.flat_map { |v| v[:aliases] || [] }).uniq
    end
  end
end
