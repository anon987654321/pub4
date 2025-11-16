#!/usr/bin/env zsh
set -euo pipefail

# LangChain.rb integration for Rails 8 apps
# Provides AI/LLM capabilities with RAG, vector search, and agents

setup_langchainrb() {
  log "Setting up LangChain.rb for AI-powered features"

  install_gem "langchainrb"
  install_gem "ruby-openai"

  if [ ! -f "config/initializers/langchain.rb" ]; then
    cat > config/initializers/langchain.rb << 'EOF'
require "langchain"

Rails.application.configure do
  config.langchain = {

    openai_api_key: ENV.fetch("OPENAI_API_KEY", ""),

    default_temperature: 0.7,

    default_model: "gpt-4-turbo-preview"

  }

end

EOF

  fi
  log "LangChain.rb installed"
}

setup_langchainrb_rails() {
  log "Setting up langchainrb_rails for ActiveRecord integration"

  install_gem "langchainrb_rails"
  install_gem "pgvector"

  if ! bin/rails runner "ActiveRecord::Base.connection.execute('SELECT 1')" 2>/dev/null; then
    log "Database not ready, skipping pgvector setup"

    return

  fi

  local migration_exists=$(bin/rails runner "Dir['db/migrate/*enable_pgvector*'].any?" 2>/dev/null || echo "false")
  if [[ "$migration_exists" == "false" ]]; then
    cat > db/migrate/$(date +%Y%m%d%H%M%S)_enable_pgvector.rb << 'EOF'
class EnablePgvector < ActiveRecord::Migration[8.0]

  def change

    enable_extension "vector"

  end

end

EOF

  fi
  log "langchainrb_rails installed. Run: rails generate langchainrb_rails:pgvector --model=YourModel"
}

setup_rag_system() {
  local model_name="${1:-Document}"

  log "Setting up RAG system for ${model_name}"
  if [ ! -f "app/services/rag_service.rb" ]; then
    mkdir -p app/services
    cat > app/services/rag_service.rb << 'EOF'

class RagService

  def initialize(model_class)

    @model_class = model_class

    @llm = Langchain::LLM::OpenAI.new(

      api_key: Rails.application.config.langchain[:openai_api_key],

      default_options: {

        temperature: Rails.application.config.langchain[:default_temperature],

        model: Rails.application.config.langchain[:default_model]

      }

    )

  end

  def ask(question)
    context = retrieve_context(question)

    prompt = build_prompt(question, context)

    response = @llm.chat(messages: [

      { role: "system", content: "You are a helpful assistant." },

      { role: "user", content: prompt }

    ])

    response.message.content

  end

  def retrieve_context(query, limit: 5)
    @model_class.similarity_search(query, limit: limit)

  end

  private
  def build_prompt(question, context)
    context_text = context.map(&:content).join("\n\n")

    <<~PROMPT

      Answer the following question based on the context provided:

      Context:
      #{context_text}

      Question: #{question}
      Answer:
    PROMPT

  end

end

EOF

  fi
  log "RAG service created. Use: RagService.new(#{model_name}).ask('your question')"
}

setup_semantic_search() {
  local model_name="${1:-Post}"

  log "Setting up semantic search for ${model_name}"
  if [ ! -f "app/controllers/concerns/semantic_searchable.rb" ]; then
    mkdir -p app/controllers/concerns
    cat > app/controllers/concerns/semantic_searchable.rb << 'EOF'

module SemanticSearchable

  extend ActiveSupport::Concern

  def semantic_search
    query = params[:q]

    return render json: { error: "Query required" }, status: :bad_request if query.blank?

    model_class = controller_name.classify.constantize
    results = model_class.similarity_search(query, limit: params[:limit] || 20)

    render json: results
  end

end

EOF

  fi
  log "Semantic search concern created. Include in controllers as needed."
}

setup_ai_content_generation() {
  log "Setting up AI content generation service"

  if [ ! -f "app/services/content_generator.rb" ]; then
    mkdir -p app/services
    cat > app/services/content_generator.rb << 'EOF'

class ContentGenerator

  def initialize

    @llm = Langchain::LLM::OpenAI.new(

      api_key: Rails.application.config.langchain[:openai_api_key],

      default_options: {

        temperature: 0.9,

        model: Rails.application.config.langchain[:default_model]

      }

    )

  end

  def generate(prompt:, max_tokens: 500)
    response = @llm.complete(

      prompt: prompt,

      max_tokens: max_tokens

    )

    response.completion

  end

  def generate_post_title(content:)
    prompt = "Generate a compelling, concise title for this content:\n\n#{content.truncate(500)}"

    generate(prompt: prompt, max_tokens: 50)

  end

  def summarize(text:, max_length: 200)
    prompt = "Summarize the following text in #{max_length} characters or less:\n\n#{text}"

    generate(prompt: prompt, max_tokens: max_length / 2)

  end

  def generate_tags(content:, max_tags: 5)
    prompt = "Generate #{max_tags} relevant tags for this content (comma-separated):\n\n#{content.truncate(500)}"

    tags_string = generate(prompt: prompt, max_tokens: 50)

    tags_string.split(",").map(&:strip).take(max_tags)

  end

end

EOF

  fi
  log "Content generator service created"
}

setup_ai_moderation() {
  log "Setting up AI content moderation"

  if [ ! -f "app/services/moderation_service.rb" ]; then
    mkdir -p app/services
    cat > app/services/moderation_service.rb << 'EOF'

class ModerationService

  def initialize

    @llm = Langchain::LLM::OpenAI.new(

      api_key: Rails.application.config.langchain[:openai_api_key],

      default_options: {

        temperature: 0.3,

        model: Rails.application.config.langchain[:default_model]

      }

    )

  end

  def moderate(content)
    prompt = <<~PROMPT

      Analyze this content for policy violations. Return JSON with:

      - safe: true/false

      - categories: array of violation types if any (hate, violence, sexual, etc)

      - reason: brief explanation

      Content: #{content}
    PROMPT

    response = @llm.chat(messages: [
      { role: "system", content: "You are a content moderation assistant." },

      { role: "user", content: prompt }

    ])

    JSON.parse(response.message.content)
  rescue JSON::ParserError

    { safe: true, categories: [], reason: "Moderation check failed" }

  end

  def safe?(content)
    result = moderate(content)

    result["safe"]

  end

end

EOF

  fi
  log "Moderation service created"
}

setup_full_langchain() {
  log "Setting up full LangChain.rb stack with Rails integration"

  setup_langchainrb
  setup_langchainrb_rails

  setup_rag_system

  setup_semantic_search

  setup_ai_content_generation

  setup_ai_moderation

  log "Full LangChain.rb stack installed. Configure OPENAI_API_KEY in .env"
}

