# frozen_string_literal: true

module MASTER
  VERSION = "4.0.0"

  def self.root
    File.expand_path("..", __dir__)
  end
end

require_relative "result"
require_relative "db"
require_relative "llm"
require_relative "pledge"
require_relative "boot"
require_relative "pipeline"
require_relative "stages/input_tank"
require_relative "stages/council_debate"
require_relative "stages/refactor_engine"
require_relative "stages/openbsd_admin"
require_relative "stages/output_tank"
