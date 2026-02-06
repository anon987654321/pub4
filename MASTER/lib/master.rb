# frozen_string_literal: true

module MASTER
  VERSION = "3.0.0"

  def self.root
    File.expand_path("..", __dir__)
  end
end

require_relative "result"
require_relative "db"
require_relative "llm"
require_relative "circuit"
require_relative "budget"
require_relative "pledge"
require_relative "typography"
require_relative "pipeline"
