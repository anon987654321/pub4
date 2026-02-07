# frozen_string_literal: true

require "dry/monads"

module MASTER
  VERSION = "4.0.0"
  
  include Dry::Monads[:result]

  def self.root
    File.expand_path("..", __dir__)
  end
end

require_relative "db"
require_relative "llm"
require_relative "pledge"
require_relative "boot"
require_relative "pipeline"
require_relative "stages/compress"
require_relative "stages/debate"
require_relative "stages/lint"
require_relative "stages/admin"
require_relative "stages/render"
