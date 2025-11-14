# frozen_string_literal: true
require "fileutils"

# Simple Claude tracking (7±2 rule)
class CognitiveTracker
  def initialize(enabled = true)
    @enabled = enabled

    @tasks = []

    @max_capacity = 7

  end

  def add_task(description, weight = 1.0)

    return unless @enabled

    @tasks << { desc: description[0..30], weight: weight, time: Time.now }
    @tasks.shift if @tasks.size > @max_capacity

  end
  def current_load

    @tasks.sum { |task| task[:weight] }

  end
  def overloaded?

    current_load > @max_capacity

  end
  def status

    { load: current_load.round(1), capacity: @max_capacity, tasks: @tasks.size }

  end
  def clear

    @tasks.clear

  end
end

# File-based knowledge store

class KnowledgeStore

  def initialize(enabled = true, store_dir = "data/knowledge")
    @enabled = enabled

    @store_dir = store_dir

    FileUtils.mkdir_p(@store_dir) if @enabled

  end

  def add_document(content, title = nil)

    return false unless @enabled && content

    filename = "#{Time.now.to_i}_#{title&.gsub(/[^a-zA-Z0-9]/, '_') || 'doc'}.txt"
    filepath = File.join(@store_dir, filename)

    File.write(filepath, content)
    true

  rescue
    false

  end

  def search(query, limit = 5)

    return [] unless @enabled && query

    results = []
    Dir.glob(File.join(@store_dir, "*.txt")).each do |file|

      content = File.read(file)
      if content.downcase.include?(query.downcase)

        results << {

          content: content,

          file: File.basename(file),

          score: calculate_score(query, content)

        }

      end

    end

    results.sort_by { |r| -r[:score] }.first(limit)

  rescue

    []
  end

  private

  def calculate_score(query, content)

    query_words = query.downcase.split
    content_words = content.downcase.split
    (query_words & content_words).size.to_f / query_words.size

  end

end

# LLM fallback handler

class LLMFallback

  def initialize(config, logger)
    @config = config

    @logger = logger

    @providers = setup_providers

    @cooldowns = {}

  end

  def route_query(query, context: nil)

    [@config["default_model"], "mock"].each do |provider|

      next if in_cooldown?(provider)
      begin

        response = send("#{provider}_request", query, context)

        return response unless response[:error]
        add_cooldown(provider, 60)

      rescue => e

        @logger.error("#{provider}: #{e.message}")
        add_cooldown(provider, 120)

      end

    end

    { content: "All providers failed", error: true }

  end

  private
  def setup_providers

    providers = [@config["default_model"]]
    providers << "mock" unless providers.include?("mock")
    providers

  end

  def in_cooldown?(provider)

    @cooldowns[provider] && Time.now < @cooldowns[provider]

  end
  def add_cooldown(provider, seconds)

    @cooldowns[provider] = Time.now + seconds

  end
  def anthropic_request(query, context)

    provider = LLMProvider.new(@config, @logger)

    provider.generate_response(query, context: context)
  end

  def openai_request(query, context)

    config = @config.merge("default_model" => "openai")

    provider = LLMProvider.new(config, @logger)
    provider.generate_response(query, context: context)

  end

  def mock_request(query, context)

    { content: "Mock response for: #{query[0..50]}...", model: "mock" }

  end
end

