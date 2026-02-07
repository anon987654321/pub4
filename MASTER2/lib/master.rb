# frozen_string_literal: true

require "dry/monads"

begin
  require "zeitwerk"
rescue LoadError
  # Zeitwerk not available, fall back to manual requires
end

module MASTER
  VERSION = "4.0.0"
  
  include Dry::Monads[:result]

  def self.root
    File.expand_path("..", __dir__)
  end
end

# Configure zeitwerk if available
if defined?(Zeitwerk)
  loader = Zeitwerk::Loader.new
  loader.push_dir("#{MASTER.root}/lib", namespace: MASTER)
  loader.setup
else
  # Fallback to manual requires
  require_relative "db"
  require_relative "llm"
  require_relative "pledge"
  require_relative "boot"
  require_relative "pipeline"
  require_relative "stages/compress"
  require_relative "stages/guard"
  require_relative "stages/debate"
  require_relative "stages/ask"
  require_relative "stages/lint"
  require_relative "stages/admin"
  require_relative "stages/render"
  require_relative "file_hygiene"
  require_relative "self_map"
  require_relative "agent"
  require_relative "agent_pool"
  require_relative "agent_firewall"
end
