# encoding: utf-8

require "langchain"
require "httparty"

class RAGSystem
  def initialize(weaviate_integration)
    @weaviate_integration = weaviate_integration
    @raft_system = Langchain::LLM::OpenAI.new(api_key: ENV["OPENAI_API_KEY"])
  end

  def generate_answer(query)
    results = @weaviate_integration.similarity_search(query, 5)
    combined_context = results.map { |r| r["content"] }.join("\n")
    response = "Based on the context:\n#{combined_context}\n\nAnswer: [Generated response based on the context]"
    response
  end

  def advanced_raft_answer(query, context)
    results = @raft_system.generate_answer("#{query}\nContext: #{context}")
    results
  end

  def process_urls(urls)
    urls.each do |url|
      process_url(url)
    end
  end

  private

  def process_url(url)
    response = HTTParty.get(url)
    content = response.body
    store_content(url, content)
  end

  def store_content(url, content)
    @weaviate_integration.add_texts([{ url: url, content: content }])
  end
end
