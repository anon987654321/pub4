#!/usr/bin/env ruby
# frozen_string_literal: true

# Demo script showing multi-language parser and conversational interface

require_relative '../lib/parser/multi_language'
require_relative '../lib/nlu'
require_relative '../lib/conversation'

puts "=" * 70
puts "MASTER2 Multi-Language Parser + NLU Demo"
puts "=" * 70
puts

# Demo 1: Multi-Language Parser
puts "Demo 1: Multi-Language Parser"
puts "-" * 70

shell_script = <<~SHELL
  #!/bin/bash
  echo "Starting deployment"
  
  ruby <<-RUBY
    class Deployer
      def deploy
        puts "Deploying application..."
      end
    end
  RUBY
  
  echo "Deployment complete"
SHELL

parser = MASTER::Parser::MultiLanguage.new(shell_script, file_path: "deploy.sh")
result = parser.parse

puts "Script type: #{result[:type]}"
puts "Embedded languages found: #{result[:embedded].keys.join(', ')}"

if result[:embedded][:ruby]
  puts "\nRuby blocks found: #{result[:embedded][:ruby].length}"
  result[:embedded][:ruby].each_with_index do |block, idx|
    puts "  Block #{idx + 1}: Lines #{block[:start_line]}-#{block[:end_line]}"
    puts "    Code preview: #{block[:code].lines.first.strip}"
  end
end

puts
puts

# Demo 2: NLU (without actual LLM)
puts "Demo 2: Natural Language Understanding"
puts "-" * 70

test_commands = [
  "refactor lib/user.rb",
  "analyze the authentication logic in lib/auth.rb",
  "show me the database models",
  "search for TODO comments",
  "fix the bug in payment.rb"
]

test_commands.each do |cmd|
  puts "\nCommand: #{cmd}"
  intent = MASTER::NLU.parse(cmd)
  puts "  Intent: #{intent[:intent]}"
  puts "  Confidence: #{intent[:confidence]}"
  puts "  Files: #{intent[:entities][:files].join(', ')}" if intent[:entities][:files]&.any?
  puts "  Method: #{intent[:method]}"
end

puts
puts

# Demo 3: Conversational Interface
puts "Demo 3: Conversational Interface"
puts "-" * 70

conversation = MASTER::Conversation.new

commands = [
  "analyze lib/user.rb",
  "refactor it",  # Should resolve "it" to lib/user.rb
  "help"
]

commands.each do |cmd|
  puts "\n> #{cmd}"
  result = conversation.process(cmd)
  puts "  Status: #{result[:status]}"
  puts "  Message: #{result[:message]}"
  if result[:files]
    puts "  Files: #{result[:files].join(', ')}"
  end
end

puts "\n\nConversation history:"
puts conversation.summary

puts
puts "=" * 70
puts "Demo complete!"
puts "=" * 70
