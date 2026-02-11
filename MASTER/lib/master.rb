require 'json'
require 'net/http'
require 'uri'
require 'fileutils'
require 'sqlite3'

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

require_relative 'engine'
require_relative 'llm'
require_relative 'autonomy'
require_relative 'persistence'
require_relative 'cli'
require_relative 'parser/multi'
require_relative 'parser/multi_language'
require_relative 'nlu'
require_relative 'conversation'
