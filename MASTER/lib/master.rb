# frozen_string_literal: true

module Master
  VERSION = "50.8"
  ROOT = File.expand_path("..", __dir__)
end

require_relative "result"
require_relative "principle"
require_relative "persona"
require_relative "sandbox"
require_relative "boot"
require_relative "llm"
require_relative "engine"
require_relative "memory"
require_relative "smells"
require_relative "openbsd"
require_relative "web"
require_relative "replicate"
require_relative "server"
require_relative "cli"
