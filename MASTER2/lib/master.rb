# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'sqlite3'
require 'dry/monads'

begin
  require 'dotenv/load'
rescue LoadError
  # No dotenv
end

module MASTER
  VERSION = '4.0.0'

  def self.root
    File.expand_path("..", __dir__)
  end
end

# Load core modules
require_relative 'db'
require_relative 'llm'
require_relative 'boot'
require_relative 'config'
require_relative 'pledge'
require_relative 'pipeline'
require_relative 'cli'

# Load stages
require_relative 'stages/compress'
require_relative 'stages/guard'
require_relative 'stages/debate'
require_relative 'stages/ask'
require_relative 'stages/lint'
require_relative 'stages/admin'
require_relative 'stages/render'

# Initialize DB and LLM on load
MASTER::DB.setup unless ENV['SKIP_DB_SETUP']
MASTER::LLM.configure unless ENV['SKIP_LLM_CONFIG']
