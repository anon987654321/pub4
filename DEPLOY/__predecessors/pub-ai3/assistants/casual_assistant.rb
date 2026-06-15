# assistants/casual_assistant.rb
#
# CasualAssistant: Provides general conversation by delegating queries
# to an LLM chain that sequentially tries multiple providers.

require_relative "llm_chain_assistant"

class CasualAssistant
  def initialize
    @chain_assistant = LLMChainAssistant.new
  end

  def respond(input)
    puts "CasualAssistant processing your input via the LLM chain..."
    response = @chain_assistant.process_query(input)
    puts "CasualAssistant: #{response}"
    response
  end
end

