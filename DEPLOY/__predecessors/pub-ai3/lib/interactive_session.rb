# encoding: utf-8
# Interactive session manager

require_relative "command_handler"
require_relative "prompt_manager"
require_relative "rag_system"
require_relative "query_cache"
require_relative "context_manager"
require_relative "rate_limit_tracker"
require_relative "weaviate_integration"
require "langchain/chunker"
require "langchain/tool/google_search"
require "langchain/tool/wikipedia"

class InteractiveSession
  def initialize
    setup_components
  end

  def start
    puts 'Welcome to EGPT. Type "exit" to quit.'
    loop do
      print "You> "
      input = gets.strip
      break if input.downcase == "exit"

      response = handle_query(input)
      puts response
    end
    puts "Session ended. Thank you for using EGPT."
  end

  private

  def setup_components
    @langchain_client = Langchain::LLM::OpenAI.new(api_key: ENV["OPENAI_API_KEY"])
    @command_handler = CommandHandler.new(@langchain_client)
    @prompt_manager = PromptManager.new
    @rag_system = RAGSystem.new(@weaviate_integration)
    @query_cache = QueryCache.new
    @context_manager = ContextManager.new
    @rate_limit_tracker = RateLimitTracker.new
    @weaviate_integration = WeaviateIntegration.new
    @google_search_tool = Langchain::Tool::GoogleSearch.new
    @wikipedia_tool = Langchain::Tool::Wikipedia.new
  end

  def handle_query(input)
    @rate_limit_tracker.increment
    @context_manager.update_context(user_id: "example_user", text: input)
    context = @context_manager.get_context(user_id: "example_user").join("\n")

    cached_response = @query_cache.fetch(input)
    return cached_response if cached_response

    combined_input = "#{input}\nContext: #{context}"
    raw_response = @rag_system.generate_answer(combined_input)
    response = @langchain_client.generate_answer("#{combined_input}. Please elaborate more.")
    
    parsed_response = @langchain_client.parse(response)
    
    @query_cache.store(input, parsed_response)
    parsed_response
  end
end
