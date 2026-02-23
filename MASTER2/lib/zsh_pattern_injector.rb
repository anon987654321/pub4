# frozen_string_literal: true

require "yaml"

# ZshPatternInjector — wires data/zsh_patterns.yml into three active enforcement points:
#   1. System prompt: tells LLM to avoid legacy forks (preventive)
#   2. shell_command tool: returns SUGGESTION when LLM uses a banned tool (enforcement)
#   3. Lint stage: detects forbidden tools in generated shell code blocks (detective)

module MASTER
  module ZshPatternInjector
    extend self

    DATA_FILE       = File.join(MASTER.root, "data", "zsh_patterns.yml")
    CONSTITUTION    = File.join(MASTER.root, "data", "constitution.yml")

    def data
      @data ||= YAML.load_file(DATA_FILE)
    rescue StandardError
      {}
    end

    # Returns { "awk" => "zsh array/string...", "sed" => "...", ... }
    # Merges data/zsh_patterns.yml (rich) with constitution.constraints.banned_tools (authoritative list)
    def forbidden
      @forbidden ||= begin
        base = (data["forbidden_commands"] || []).each_with_object({}) do |entry, h|
          h[entry["command"]] = entry["replacement"]
        end
        # constitution.yml is ONE_SOURCE for the banned tool list — supplement base with any extras
        extra = begin
          YAML.safe_load_file(CONSTITUTION)&.dig("constraints", "banned_tools") || []
        rescue StandardError
          []
        end
        extra.each { |tool| base[tool.to_s] ||= "a native zsh equivalent" }
        base
      end
    end

    # Compact section injected into every system prompt.
    def prompt_section
      return "" if forbidden.empty?

      lines = ["Zsh native patterns (mandatory — never use legacy forks in shell code):"]
      forbidden.each { |cmd, replacement| lines << "  NEVER `#{cmd}` → #{replacement}" }
      lines << "  Use zsh glob qualifiers (**/*.rb(.) etc.) instead of find."
      lines << "  Use doas, not sudo, on OpenBSD."
      lines.join("\n")
    rescue StandardError
      ""
    end

    # Returns the name of the first banned tool found in +cmd+, or nil.
    def banned_tool_in?(cmd)
      forbidden.keys.find { |tool| cmd.match?(/\b#{Regexp.escape(tool)}\b/) }
    end

    # Returns the zsh replacement hint for a given tool name.
    def replacement_for(tool)
      forbidden[tool] || "a zsh native equivalent"
    end

    # Scans free-form text (LLM output) for any use of banned tools.
    # Returns array of { tool:, line:, hint: } hashes.
    def scan_violations(text)
      return [] if forbidden.empty?

      violations = []
      text.each_line do |line|
        forbidden.each do |tool, replacement|
          next unless line.match?(/\b#{Regexp.escape(tool)}\b/)

          violations << { tool: tool, line: line.strip[0..120], hint: replacement }
        end
      end
      violations
    end
  end
end
