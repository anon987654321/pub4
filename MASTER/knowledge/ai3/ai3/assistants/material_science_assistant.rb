# MaterialScienceAssistant – Provides material science assistance.
#
# Restored full logic from the old version.
require "openai"
require_relative "../lib/weaviate_helper"
module Assistants
  class MaterialScienceAssistant
    def initialize
      @client = OpenAI::Client.new(api_key: ENV['OPENAI_API_KEY'])
      @weaviate_helper = WeaviateHelper.new
    end

    def handle_material_query(query)
      relevant_docs = @weaviate_helper.query_vector_search(embed_query(query))
      context = build_context_from_docs(relevant_docs)
      prompt = build_prompt(query, context)
      generate_response(prompt)
    end

    private

    def embed_query(query)
      [0.1, 0.2, 0.3]  # Placeholder embedding
    end

    def build_context_from_docs(docs)
      docs.map { |doc| doc[:properties] }.join(" \n")
    end

    def build_prompt(query, context)
      "Material Science Context:\n#{context}\n\nUser Query:\n#{query}\n\nResponse:"
    end

    def generate_response(prompt)
      response = @client.completions(parameters: {
        model: "text-davinci-003",
        prompt: prompt,
        max_tokens: 150
      })
      response['choices'][0]['text'].strip
    rescue StandardError => e
      "Error generating response: #{e.message}"
    end
  end
end
