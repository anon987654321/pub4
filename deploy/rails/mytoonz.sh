```zsh
#!/usr/bin/env zsh
set -euo pipefail

# MyToonz: AI-Powered Personalized Comic Strip Generator
# Generates authentic comic strips from user's daily stories using Replicate AI

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="mytoonz"

if [[ -f "${BASE_DIR}/__shared.sh" ]]; then
    source "${BASE_DIR}/__shared.sh"
else
    echo "Error: __shared.sh not found in ${BASE_DIR}" >&2
    exit 1
fi

main() {
    log "Starting MyToonz setup..."

    setup_full_app "$APP_NAME"
    setup_mytoonz_specific

    setup_frontend

    log "✓ MyToonz setup complete!"
    log "→ Start server: cd mytoonz && bin/rails server -p 10008"
    log "→ Visit: http://localhost:10008"
}

setup_mytoonz_specific() {
    log "Setting up MyToonz-specific features..."

    cd "$BASE_DIR/$APP_NAME"

    install_gem "httparty"
    install_gem "redis"
    install_gem "sidekiq"

    setup_storage
    create_replicate_service
    create_models
    create_controllers
    create_jobs
    setup_routes
    create_initializers

    log "✓ MyToonz-specific setup complete"
}

setup_storage() {
    log "Setting up Active Storage..."
    bin/rails active_storage:install
    bin/rails db:migrate
}

create_replicate_service() {
    log "Creating Replicate AI integration service..."

    mkdir -p app/services
    cat > app/services/replicate_service.rb << 'RUBY'
require 'httparty'

class ReplicateService
  include HTTParty

  base_uri 'https://api.replicate.com/v1'

  def initialize
    @api_token = ENV['REPLICATE_API_TOKEN']
    raise ArgumentError, "REPLICATE_API_TOKEN not set" unless @api_token
  end

  def generate_comic_strip(prompt:, style: "comic", user_photo_url: nil)
    validate_input(prompt, style, user_photo_url)

    model = select_model(style)
    input = build_input(prompt, style, user_photo_url)

    response = self.class.post(
      '/predictions',
      headers: headers,
      body: {
        version: model_id)
    response = self.class.get(
      "/predictions/#{prediction_id}",
      headers: headers
    )
    handle_response(response)
  end

  private

  def headers
    {
      'Authorization' => "Token #{@api_token}",
      'Content-Type' => 'application/json'
    }
  end

  def validate_input(prompt, style, user.to_s.strip.empty?
    raise ArgumentError, "Invalid style" unless %w[comic manga cartoon].include?(style)
    return unless user_photo_url

    unless user_photo_url =~ URI(style)
    {
      comic: { version: "st2a78e934b3ba6e2a525255b1aa35c5565e08b" },
      manga: { version: "cjwbw/kohaku:1b1ffa5cafd2b8e2b8d2b8e" },
      cartoon: { version: "cartoon-line-art:7b0e658d1b1ffa5cafd75874d4c60c0d475e" }
    }[style.to_sym]
  end

 image] = user_photo_url if user_photo_url
    input    when 200..299
      response.parsed_response
    when 401
      raise "Unauthorized: Check your REPLICATE_API_TOKEN"
    when 404
      raise "Resource not found"
    when 429
      raise "Rate limit exceeded"
    else
      raise "API error: #{response.code} - #{responsecreate_models() {
    log "Creating models..."

    bin/_url:string \
        status:string \
        replicate_prediction_id:string \
        generated_images:json

    bin/rails db:migrate
}

create_controllers() {
    log "Creating controllers..."

    bin/rails generate controller ComicStrips index create show
}

create_jobs() {
    log "Creating background jobs..."

    mkdir -p app/jobs
    cat > app/jobs/generate_comic_job.rb << 'RUBY'
class GenerateComicJob < ApplicationJob
  queue_as :default

  def perform(comic_strip_id)
    comic_strip = ComicStrip.find(comic_strip_id)
    comic_strip.update!(status: 'processing')

    service = ReplicateService.new
    prediction = service.generate_comic_strip(
      prompt: comic_strip.prompt,
      style: comic_strip.style,
      user_photo_url: comic_strip.user_photo_url
    )

    comic_strip.update!(
      replicate_prediction_id: prediction['id'],
      status: 'submitted'
    )
  rescue => e
    comic_strip.update!(status: 'failed')
    raise e
  end
end
RUBY
}

setup_routes() {
    logRUBY'
Rails.application.routes.draw do
  resources :comic_strips, only: [:index, :create, :show]
  root 'comic_strips#index'
end
RUBY
}

create_initializers() {
    log "Creating initializers..."

    mkdir -p config/initializers
    cat > config/initializers/sidekiq.rb << 'RUBY'
Sidekiq.configure_server do |config|
  config.redis = { url: ENV['REDIS_URL'] || 'redis://localhost:6379/0' }
end

Sidekiq.configure_client do |config|
  config.redis = { url: ENV['REDIS_URL'] || 'redis://_DIR/$APP_NAME"
    yarn install
}

main "$@"
```
