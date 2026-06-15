# assistants/llm_chain_assistant.rb
#
# LLMChainAssistant: Processes a query through a chain of LLM providers.
#
# The chain sequentially queries:
#   1. OpenAI providers with various chat models:
#      - "o3-mini-high"
#      - "o3-mini"
#      - "o1"
#      - "o1-mini"
#      - "gpt-4o"
#      - "gpt-4o-mini"
#   2. Anthropic Claude
#   3. Google Gemini
#   4. Weaviate vector search (via its ask method)
#
# Ensure required environment variables are set:
#   - OPENAI_API_KEY, ANTHROPIC_API_KEY, GOOGLE_GEMINI_API_KEY,
#     WEAVIATE_URL, WEAVIATE_API_KEY

class LLMChainAssistant
  def initialize
    @llm_chain = []

    # OpenAI providers with various chat models
    @llm_chain << {
      name: "openai_o3_mini_high",
      llm: Langchain::LLM::OpenAI.new(
        api_key: ENV["OPENAI_API_KEY"],
        default_options: { temperature: 0.7, chat_model: "o3-mini-high" }
      )
    }
    @llm_chain << {
      name: "o3_mini",
      llm: Langchain::LLM::OpenAI.new(
        api_key: ENV["OPENAI_API_KEY"],
        default_options: { temperature: 0.7, chat_model: "o3-mini" }
      )
    }
    @llm_chain << {
      name: "o1",
      llm: Langchain::LLM::OpenAI.new(
        api_key: ENV["OPENAI_API_KEY"],
        default_options: { temperature: 0.7, chat_model: "o1" }
      )
    }
    @llm_chain << {
      name: "o1_mini",
      llm: Langchain::LLM::OpenAI.new(
        api_key: ENV["OPENAI_API_KEY"],
        default_options: { temperature: 0.7, chat_model: "o1-mini" }
      )
    }
    @llm_chain << {
      name: "gpt_4o",
      llm: Langchain::LLM::OpenAI.new(
        api_key: ENV["OPENAI_API_KEY"],
        default_options: { temperature: 0.7, chat_model: "gpt-4o" }
      )
    }
    @llm_chain << {
      name: "gpt_4o_mini",
      llm: Langchain::LLM::OpenAI.new(
        api_key: ENV["OPENAI_API_KEY"],
        default_options: { temperature: 0.7, chat_model: "gpt-4o-mini" }
      )
    }

    # Anthropic Claude provider
    @llm_chain << {
      name: "anthropic_claude",
      llm: Langchain::LLM::Anthropic.new(api_key: ENV["ANTHROPIC_API_KEY"])
    }

    # Google Gemini provider
    @llm_chain << {
      name: "google_gemini",
      llm: Langchain::LLM::GoogleGemini.new(api_key: ENV["GOOGLE_GEMINI_API_KEY"])
    }

    # Weaviate vector search client
    @weaviate_client = Langchain::Vectorsearch::Weaviate.new(
      url: ENV["WEAVIATE_URL"],
      api_key: ENV["WEAVIATE_API_KEY"],
      index_name: "Documents",
      llm: Langchain::LLM::OpenAI.new(api_key: ENV["OPENAI_API_KEY"])
    )
    @llm_chain << { name: "weaviate", llm: nil }  # Special handling for Weaviate below
  end

  def process_query(query)
    @llm_chain.each do |provider|
      puts "Querying #{provider[:name]}..."
      begin
        if provider[:name] == "weaviate"
          response = @weaviate_client.ask(question: query)
          completion = response.completion
        else
          response = provider[:llm].complete(prompt: query)
          completion = response.completion
        end

        if valid_response?(completion)
          puts "Response from #{provider[:name]}: #{completion}"
          return completion
        end
      rescue StandardError => e
        puts "Error querying #{provider[:name]}: #{e.message}"
      end
    end
    "No valid response obtained from any provider."
  end

  private

  def valid_response?(response)
    response && !response.strip.empty?
  end
end

