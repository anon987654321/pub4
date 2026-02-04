# frozen_string_literal: true
require "singleton"
require_relative "result"
require_relative "principle"
require_relative "sandbox"
require_relative "boot"
require_relative "llm"
require_relative "engine"
require_relative "cli"

module Master
  VERSION = "50.0"
  ROOT = File.expand_path("..", __dir__)
end
