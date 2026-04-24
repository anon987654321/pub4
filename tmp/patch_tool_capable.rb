# frozen_string_literal: true

# Move TOOL_CAPABLE patterns from hardcoded regex in agent.rb to data/models.yml
# and update agent.rb to load them dynamically.

BASE = "/home/dev/pub4/MASTER"

# --- 1: Add tool_capable_prefixes to models.yml ---
models_yml = File.read("#{BASE}/data/models.yml")

unless models_yml.include?("tool_capable_prefixes")
  addition = <<~'YAML'

# Model name prefixes that support tool use (anchored match).
# Agent.tool_capable? checks model IDs against these prefixes.
tool_capable_prefixes:
  - claude
  - gpt-4
  - gpt-4o
  - gemini
  - mistral
  - mixtral
  - llama-3.1
  - llama-3.3
  - qwen
  - command-r
  - deepseek
  - stepfun
  - nvidia
  - nemotron
  - meta/meta-llama
  - anthropic/claude
  - openai/gpt
  - google/gemini
  YAML

  models_yml += addition
  File.write("#{BASE}/data/models.yml", models_yml)
  puts "models.yml: added tool_capable_prefixes"
end

# --- 2: Update agent.rb to load from YAML ---
agent_rb = File.read("#{BASE}/lib/master/agent.rb")

# Replace the hardcoded TOOL_CAPABLE_RE with a dynamic loader
old_re = <<~'OLD'
    # Tool-capable model whitelist — anchored regex, not substring match.
    # See note at tool_capable? for why the previous `include?` check was unsafe.
    TOOL_CAPABLE_RE = %r{
      \A(?:
        (?:claude|gpt-4|gpt-4o|gemini|mistral|mixtral)
        | (?:llama-3\.[13])
        | (?:qwen|command-r|deepseek|stepfun|nvidia|nemotron)
        | (?:meta/meta-llama.+)
        | (?:anthropic/claude.+)
        | (?:openai/gpt.+)
        | (?:google/gemini.+)
      )(?:[:@/\-.].+)?\z
    }ix.freeze
OLD

new_re = <<~'NEW'
    # Tool-capable model whitelist — loaded from data/models.yml.
    # Anchored regex built from tool_capable_prefixes list.
    def self.build_tool_capable_re
      yml_path = File.join(Master::ROOT, "data", "models.yml")
      prefixes = YAML.safe_load_file(yml_path).fetch("tool_capable_prefixes", [])
      escaped = prefixes.map { |p| Regexp.escape(p) }
      Regexp.new("\\A(?:#{escaped.join("|")})(?:[:\\/@\\-.].+)?\\z", Regexp::IGNORECASE).freeze
    end

    TOOL_CAPABLE_RE = build_tool_capable_re
NEW

if agent_rb.include?("TOOL_CAPABLE_RE = %r{")
  agent_rb.sub!(old_re.strip, new_re.strip)
  # Need to require yaml at top if not already
  unless agent_rb.include?('require "yaml"')
    agent_rb.sub!('require "digest"', "require \"digest\"\nrequire \"yaml\"")
  end
  File.write("#{BASE}/lib/master/agent.rb", agent_rb)
  puts "agent.rb: TOOL_CAPABLE_RE now loads from data/models.yml"
else
  puts "agent.rb: TOOL_CAPABLE_RE pattern not found (already changed?)"
end
