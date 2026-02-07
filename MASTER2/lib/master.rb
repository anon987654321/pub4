# frozen_string_literal: true

require "json"
require "fileutils"
require "sqlite3"
require "yaml"
require "timeout"

begin
  require "dotenv/load"
rescue LoadError
  # No dotenv
end

begin
  require "ruby_llm"
rescue LoadError
  # ruby_llm not available
end

begin
  require "dry/monads"
rescue LoadError
  # dry-monads not available
end

module MASTER
  VERSION = "4.0.0"

  def self.root
    File.expand_path("..", __dir__)
  end
end

# Core infrastructure
require_relative "paths"
require_relative "db"
require_relative "llm"
require_relative "pledge"
require_relative "boot"
require_relative "file_hygiene"
require_relative "self_map"

# Pipeline
require_relative "pipeline"

# Stages
require_relative "stages/compress"
require_relative "stages/guard"
require_relative "stages/debate"
require_relative "stages/ask"
require_relative "stages/lint"
require_relative "stages/admin"
require_relative "stages/render"

# Agent system
require_relative "agent"
require_relative "shell"
