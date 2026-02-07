# frozen_string_literal: true

module MASTER
  VERSION = "4.0.0"
  def self.root = File.expand_path("..", __dir__)
end

require "fileutils"

require_relative "paths"
require_relative "result"
require_relative "db"
require_relative "llm"
require_relative "memory"
require_relative "pledge"
require_relative "boot"
require_relative "stages"
require_relative "pipeline"

# Agent system
require_relative "agent"
require_relative "agent_pool"
require_relative "agent_firewall"

# Optional
require_relative "auto_install"
