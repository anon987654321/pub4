# frozen_string_literal: true
require "singleton"

module Master
  VERSION = "50.3"
  ROOT = File.expand_path("..", __dir__)
end

require_relative "result"
require_relative "principle"
require_relative "sandbox"
require_relative "boot"
require_relative "llm"
require_relative "engine"
require_relative "memory"
require_relative "server"
require_relative "cli"
