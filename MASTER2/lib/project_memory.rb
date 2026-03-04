# frozen_string_literal: true

# ProjectMemory — persistent goal and context across sessions and models.
#
# Stores a compact context file at .master/context.yml in the project root.
# Injected into every LLM system message regardless of model tier.
# Small by design (< 400 tokens) so free models receive it too.
#
# Public interface:
#   ProjectMemory.load(root:)        → hash with :goal, :stack, :decisions, :constraints
#   ProjectMemory.save(root:, **kw)  → writes .master/context.yml
#   ProjectMemory.inject(root:)      → String for system message injection

module MASTER
  module ProjectMemory
    extend self

    FILE = ".master/context.yml"
    MAX_DECISIONS = 8  # keep only the 8 most recent decisions

    # Load project context. Returns empty hash if file absent.
    def load(root: Dir.pwd)
      path = File.join(root, FILE)
      return {} unless File.exist?(path)

      YAML.safe_load_file(path) || {}
    rescue StandardError
      {}
    end

    # Save/merge context. Silently creates .master/ if absent.
    def save(root: Dir.pwd, **fields)
      dir  = File.join(root, ".master")
      path = File.join(dir, "context.yml")
      Dir.mkdir(dir) unless Dir.exist?(dir)

      current = load(root: root)
      fields.each do |k, v|
        key = k.to_s
        if key == "decisions" && v
          # Append new decision; keep most recent MAX_DECISIONS (newest last)
          current["decisions"] = (Array(current["decisions"]) + [v.to_s.strip]).last(MAX_DECISIONS)
        elsif v && !v.to_s.strip.empty?
          current[key] = v.to_s.strip
        end
      end
      current["updated"] = Time.now.strftime("%Y-%m-%d")

      File.write(path, YAML.dump(current))
      current
    end

    # Build a compact system-message block. Returns "" when context is empty.
    def inject(root: Dir.pwd)
      ctx = load(root: root)
      return "" if ctx.empty?

      lines = ["PROJECT CONTEXT:"]
      lines << "  goal: #{ctx['goal']}"              if ctx["goal"]
      lines << "  stack: #{ctx['stack']}"            if ctx["stack"]
      lines << "  constraints: #{ctx['constraints']}" if ctx["constraints"]
      if ctx["decisions"]&.any?
        lines << "  recent decisions:"
        Array(ctx["decisions"]).each { |d| lines << "    · #{d}" }
      end
      lines.join("\n")
    end
  end
end
