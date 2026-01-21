#!/usr/bin/env ruby
# frozen_string_literal: true

ENV["NO_AUTO_INSTALL"] = "1"

require_relative "cli"

puts "Testing CLI Integration..."
puts

begin
  puts "✓ CLI class loaded successfully"
  
  puts "\nTesting constants..."
  
  if CLI::ACCESS_LEVELS.key?(:sandbox) && CLI::ACCESS_LEVELS.key?(:user) && CLI::ACCESS_LEVELS.key?(:admin)
    puts "✓ ACCESS_LEVELS defined with all tiers"
  else
    puts "✗ ACCESS_LEVELS missing tiers"
    exit 1
  end
  
  if CLI::COMMAND_ALIASES["/h"] == "/help" && CLI::COMMAND_ALIASES["/p"] == "/provider"
    puts "✓ COMMAND_ALIASES defined correctly"
  else
    puts "✗ COMMAND_ALIASES incorrect"
    exit 1
  end
  
  puts "\nTesting module loading..."
  
  begin
    require_relative "cli_config"
    puts "✓ cli_config.rb loads without errors"
  rescue => e
    puts "✗ cli_config.rb failed: #{e.message}"
    exit 1
  end
  
  begin
    require_relative "cli_webchat"
    puts "✓ cli_webchat.rb loads without errors"
  rescue => e
    puts "✗ cli_webchat.rb failed: #{e.message}"
    exit 1
  end
  
  begin
    require_relative "cli_api"
    puts "✓ cli_api.rb loads without errors"
  rescue => e
    puts "✗ cli_api.rb failed: #{e.message}"
    exit 1
  end
  
  puts "\nTesting Config class..."
  
  config = Convergence::Config.new
  if config.respond_to?(:mode) && config.respond_to?(:provider)
    puts "✓ Config class has required methods"
  else
    puts "✗ Config class missing methods"
    exit 1
  end
  
  puts "\nTesting WebChatClient class..."
  
  if Convergence::WebChatClient::PROVIDERS.key?(:duckduckgo)
    puts "✓ WebChatClient PROVIDERS defined"
  else
    puts "✗ WebChatClient PROVIDERS missing"
    exit 1
  end
  
  if Convergence::WebChatClient.instance_methods.include?(:send_message)
    puts "✓ WebChatClient has send_message method"
  else
    puts "✗ WebChatClient missing send_message method"
    exit 1
  end
  
  puts "\nTesting APIClient class..."
  
  if Convergence::APIClient::PROVIDERS.key?(:openrouter)
    puts "✓ APIClient PROVIDERS defined"
  else
    puts "✗ APIClient PROVIDERS missing"
    exit 1
  end
  
  if Convergence::APIClient.instance_methods.include?(:send)
    puts "✓ APIClient has send method"
  else
    puts "✗ APIClient missing send method"
    exit 1
  end
  
  puts "\nTesting RAG class..."
  
  rag = RAG.new
  if rag.respond_to?(:search) && rag.respond_to?(:search_with_rrf)
    puts "✓ RAG has search and search_with_rrf methods"
  else
    puts "✗ RAG missing search methods"
    exit 1
  end
  
  puts "\n" + "="*50
  puts "All integration tests passed! ✓"
  puts "="*50
  
rescue => e
  puts "\n✗ Test failed: #{e.message}"
  puts e.backtrace.first(5)
  exit 1
end
