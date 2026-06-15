# lib/base_assistant.rb
#
# BaseAssistant: Core assistant that interfaces with Langchain's LLM.
# Provides a chat method to process user prompts and return completions.

require "logger"
require "langchain"
require_relative "tool_manager"

class BaseAssistant
  attr_reader :llm, :logger, :tool_manager

  def initialize
    @logger = Logger.new("logs/assistant.log", "daily")
    @logger.level = Logger::INFO
    @llm = Langchain::LLM::OpenAI.new(
      api_key: ENV["OPENAI_API_KEY"],
      default_options: { temperature: 0.7, chat_model: "o3-mini-high" }
    )
    @tool_manager = ToolManager.new
    @logger.info("BaseAssistant initialized.")
  end

  def chat(prompt)
    @logger.info("User prompt: #{prompt}")
    response = @llm.chat(messages: [{ "role" => "user", "content" => prompt }])
    @logger.info("Assistant response: #{response.chat_completion}")
    response.chat_completion
  rescue StandardError => e
    @logger.error("Chat error: #{e.message}")
    "Sorry, an error occurred."
  end

  # Alias for backward compatibility
  alias respond chat
end

