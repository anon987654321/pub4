# frozen_string_literal: true

module Master
  VERSION = "50.8"
  ROOT = File.expand_path("..", __dir__)
  
  # Default persona: ultra-brief, ultra-clear (Strunk & White)
  PERSONA = {
    name: "default",
    traits: ["direct", "concise", "clear"],
    style: "Strunk & White",
    rules: [
      "Omit needless words",
      "Use active voice",
      "Be specific, not vague",
      "One idea per sentence",
      "Prefer short words"
    ]
  }.freeze
end

require_relative "result"
require_relative "principle"
require_relative "sandbox"
require_relative "boot"
require_relative "llm"
require_relative "engine"
require_relative "memory"
require_relative "smells"
require_relative "openbsd"
require_relative "web"
require_relative "server"

# New features v50.8
require_relative "memory/git_backed"
require_relative "git/smart_hooks"
require_relative "voice/interface"
require_relative "test_gen/rspec_generator"
require_relative "graph/knowledge"
require_relative "conflicts/resolver"
require_relative "agents/principle_agents/base"
require_relative "agents/principle_agents/agents"
require_relative "evolution/meta"

require_relative "cli"
