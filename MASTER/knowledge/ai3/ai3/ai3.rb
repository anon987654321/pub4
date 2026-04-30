#!/usr/bin/env ruby
# frozen_string_literal: true
# 
# IMPORTANT: gem install --user-install ruby-openai weaviate-ruby langchainrb && export GEM_HOME=$HOME/.gem/ruby/3.3 GEM_PATH=$HOME/.gem/ruby/3.3:$GEM_PATH PATH=$HOME/.gem/ruby/3.3/bin:$PATH

require "logger"
require "json"
require "langchain"
require_relative "assistants/casual_assistant"

# Setup global logger
$logger = Logger.new("ai3.log", "daily")
$logger.level = Logger::INFO

# Load prompt configuration from "prompts.json" if it exists
PROMPTS_FILE = "../prompts.json"
if File.exist?(PROMPTS_FILE)
  $prompts = JSON.parse(File.read(PROMPTS_FILE))
else
  $prompts = {}
end

class AI3
  def initialize
    @assistant = CasualAssistant.new
  end

  def start
    puts "Welcome to AI^3. Type `exit` to quit."
    loop do
      print "AI³> "
      input = gets.chomp.strip
      break if input.downcase == "exit"
      response = @assistant.respond(input)
      puts "\nResponse: #{response}\n"
    end
    puts "Goodbye!"
  end
end

AI3.new.start

