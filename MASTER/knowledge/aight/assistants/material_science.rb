# frozen_string_literal: true

# MaterialScienceAssistant: Provides material science assistance capabilities

require 'openai'
require_relative 'weaviate_helper'

class MaterialScienceAssistant
  def initialize
    @client = OpenAI::Client.new(api_key: ENV.fetch('OPENAI_API_KEY', nil))
    @weaviate_helper = WeaviateHelper.new
  end

  def handle_material_query(query)
    # Retrieve relevant documents from Weaviate
    relevant_docs = @weaviate_helper.query_vector_search(embed_query(query))
    context = build_context_from_docs(relevant_docs)

    # Generate a response using OpenAI API with context augmentation
    prompt = build_prompt(query, context)
    generate_response(prompt)
  end

  private

  def embed_query(_query)
    # Embed the query to generate vector (placeholder)
    [0.1, 0.2, 0.3] # Replace with actual embedding logic if available
  end

  def build_context_from_docs(docs)
    docs.map { |doc| doc[:properties] }.join(" \n")
  end

  def build_prompt(query, context)
    "Material Science Context:\n#{context}\n\nUser Query:\n#{query}\n\nResponse:"
  end

  def generate_response(prompt)
    response = @client.completions(parameters: {
                                     model: 'text-davinci-003',
                                     prompt: prompt,
                                     max_tokens: 150
                                   })

    response['choices'][0]['text'].strip
  rescue StandardError => e
    "An error occurred while generating the response: #{e.message}"
  end
end
