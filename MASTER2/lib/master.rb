require 'json'
require 'net/http'
require 'uri'
require 'fileutils'
require 'sqlite3'
require 'dotenv/load'

module MASTER
  VERSION = '4.0.0'
end

require_relative 'config'
require_relative 'engine'
require_relative 'llm'
require_relative 'tools/shell'
require_relative 'tools/web_search'
require_relative 'autonomy'
require_relative 'persistence'
require_relative 'monitoring'
require_relative 'cli'
