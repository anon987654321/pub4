require 'json'
require 'net/http'
require 'uri'
require 'fileutils'
require 'sqlite3'

begin
  require 'dotenv/load'
  Dotenv.load
rescue LoadError
  # No dotenv, skip
end

module MASTER
  VERSION = '4.0.0'
end

require_relative 'engine'
require_relative 'llm'
require_relative 'autonomy'
require_relative 'persistence'
require_relative 'monitoring'
require_relative 'cli'
