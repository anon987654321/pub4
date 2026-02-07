# frozen_string_literal: true

module MASTER
  VERSION = "4.0.0"
  def self.root = File.expand_path("..", __dir__)
end

require "fileutils"

# Core
require_relative "paths"
require_relative "result"
require_relative "db"
require_relative "llm"
require_relative "memory"
require_relative "pledge"

# UI
require_relative "ui"
require_relative "help"
require_relative "autocomplete"
require_relative "progress"
require_relative "undo"
require_relative "dashboard"
require_relative "commands"

# Pipeline
require_relative "boot"
require_relative "stages"
require_relative "pipeline"

# Tools
require_relative "shell"
require_relative "introspection"
require_relative "problem_solver"
require_relative "chamber"
require_relative "evolve"
require_relative "converge"
require_relative "edge_tts"
require_relative "momentum"

# Agents
require_relative "agent"
require_relative "agent_pool"
require_relative "agent_firewall"

# Optional
require_relative "auto_install"
