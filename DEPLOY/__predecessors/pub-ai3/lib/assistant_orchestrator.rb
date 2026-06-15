# frozen_string_literal: true

# Assistant Orchestrator - Unified request processing framework
# Migrated and enhanced from ai3_old/assistants/assistant_api.rb

require_relative 'universal_scraper'
require_relative 'query_cache'
require_relative 'filesystem_utils'

class AssistantOrchestrator
  attr_reader :llm_wrapper, :scraper, :file_system_tool, :query_cache

  def initialize(llm: nil)
    @llm_wrapper = llm || create_default_llm
    @scraper = UniversalScraper.new
    @file_system_tool = FilesystemTool.new
    @query_cache = QueryCache.new
  end

  # Unified request processing framework
  def process_request(request)
    validate_request(request)

    case request[:action]
    when 'scrape_data'
      scrape_data(request[:urls])
    when 'query_llm'
      query_llm(request[:prompt])
    when 'create_file'
      create_file(request[:file_path], request[:content])
    when 'cached_query'
      cached_query_llm(request[:prompt])
    when 'batch_process'
      batch_process(request[:requests])
    else
      "Unknown action: #{request[:action]}"
    end
  rescue StandardError => e
    handle_error(e, request)
  end

  # Action routing: scrape_data
  def scrape_data(urls)
    return 'No URLs provided' unless urls && !urls.empty?

    @scraper.scrape(urls)
  end

  # Action routing: query_llm
  def query_llm(prompt)
    return 'No prompt provided' unless prompt && !prompt.empty?

    response = @llm_wrapper.query_openai(prompt)
    puts "Assistant Response: #{response}"
    response
  end

  # Action routing: create_file with enhanced validation
  def create_file(file_path, content)
    return 'No file path provided' unless file_path && !file_path.empty?
    return 'No content provided' unless content

    @file_system_tool.write_file(file_path, content)
    "File created successfully: #{file_path}"
  end

  # Enhanced action: cached query for cognitive efficiency
  def cached_query_llm(prompt)
    return 'No prompt provided' unless prompt && !prompt.empty?

    # Check cache first
    cached_response = @query_cache.retrieve(prompt)
    if cached_response
      puts 'Cache hit! Returning cached response.'
      return cached_response
    end

    # Query LLM and cache response
    response = query_llm(prompt)
    @query_cache.add(prompt, response)
    response
  end

  # Batch processing for cognitive load management
  def batch_process(requests)
    return 'No requests provided' unless requests && requests.is_a?(Array)

    results = []
    requests.each_with_index do |request, index|
      result = process_request(request)
      results << { index: index, status: 'success', result: result }
    rescue StandardError => e
      results << { index: index, status: 'error', error: e.message }
    end
    results
  end

  # Get orchestrator statistics for cognitive monitoring
  def stats
    {
      cache_stats: @query_cache.stats,
      total_requests_processed: @requests_processed || 0,
      active_tools: {
        llm_wrapper: !@llm_wrapper.nil?,
        scraper: !@scraper.nil?,
        file_system_tool: !@file_system_tool.nil?,
        query_cache: !@query_cache.nil?
      }
    }
  end

  private

  def create_default_llm
    # Create a basic LLM wrapper if none provided
    Class.new do
      def query_openai(prompt)
        "Mock LLM response for: #{prompt}"
      end
    end.new
  end

  def validate_request(request)
    raise ArgumentError, 'Request must be a hash' unless request.is_a?(Hash)
    raise ArgumentError, 'Request must include :action' unless request.key?(:action)
  end

  def handle_error(error, request)
    error_message = "Error processing request #{request[:action]}: #{error.message}"
    puts "ERROR: #{error_message}"
    { error: error_message, request: request }
  end
end
